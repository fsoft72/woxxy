import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/funcs/debug.dart';
import 'package:woxxy/funcs/format.dart';
import 'package:woxxy/funcs/throttle.dart';
import 'package:woxxy/funcs/transfer_id.dart';

import 'network/send_service.dart';
import '../config/transfer_constants.dart';

/// Sends one file; returns when the transfer finished. Matches [NetworkService.sendFile] for one peer.
typedef SendFileFunction = Future<String> Function(
    String transferId, String filePath, FileTransferProgressCallback onProgress);

/// Cancels an active transfer by id.
typedef CancelTransferFunction = bool Function(String transferId);

/// A file waiting in, or finished by, the send queue.
class QueuedFile {
  final String path;
  final String name;
  final int size;
  bool isCompleted = false;
  bool isFailed = false;
  String? errorMessage;

  QueuedFile(this.path, this.name, this.size);
}

/// Sends files to one peer one after the other and exposes progress for the UI.
class SendQueueController extends ChangeNotifier {
  final SendFileFunction _send;
  final CancelTransferFunction _cancel;
  final ProgressThrottle _throttle;
  final String Function(String filename) _idGenerator;
  final Duration _pauseAfterSuccess;
  final Duration _pauseAfterFailure;

  /// Called with a short user facing message (success, failure, cancelled).
  final void Function(String message)? onMessage;

  final Queue<QueuedFile> _queue = Queue<QueuedFile>();
  final List<QueuedFile> _completed = [];
  bool _processing = false;
  int _generation = 0; // Bumped by cancelAll so a loop (or a late result) of an older run can tell it is stale
  bool _disposed = false;
  String? _activeTransferId;

  String _currentFileName = '';
  double _progress = 0;
  double _speedMBps = 0;
  bool _transferComplete = false;
  bool _isTransferring = false;
  bool _preparing = false;
  int _totalCompleted = 0;

  SendQueueController({
    required SendFileFunction send,
    required CancelTransferFunction cancel,
    this.onMessage,
    ProgressThrottle? throttle,
    String Function(String filename)? idGenerator,
    Duration pauseAfterSuccess = const Duration(milliseconds: 500),
    Duration pauseAfterFailure = const Duration(seconds: 1),
  })  : _send = send,
        _cancel = cancel,
        _throttle = throttle ?? ProgressThrottle(),
        _idGenerator = idGenerator ?? generateTransferId,
        _pauseAfterSuccess = pauseAfterSuccess,
        _pauseAfterFailure = pauseAfterFailure;

  /// Files not sent yet; the first one is being sent while [isTransferring].
  UnmodifiableListView<QueuedFile> get queue => UnmodifiableListView(_queue);

  /// Files already sent or failed, oldest first.
  UnmodifiableListView<QueuedFile> get completed => UnmodifiableListView(_completed);
  String get currentFileName => _currentFileName;

  /// Progress of the current file, 0 to 100.
  double get progress => _progress;
  double get speedMBps => _speedMBps;
  bool get transferComplete => _transferComplete;
  bool get isTransferring => _isTransferring;

  /// True from the start of a file until its first progress report: the file is being hashed
  /// and the connection opened, so no byte moved yet.
  bool get isPreparing => _preparing;
  int get totalCompleted => _totalCompleted;

  /// True while the controller is sending a file or has files waiting.
  bool get hasWork => _queue.isNotEmpty || _processing;

  /// Adds files to the queue and starts sending if idle.
  ///
  /// Paths that are not readable files (a dropped folder, a file deleted meanwhile) are skipped
  /// and reported through [onMessage]; they never leave the controller in a busy state.
  Future<void> addFiles(List<String> filePaths) async {
    if (filePaths.isEmpty) return;
    zprint('📁 Adding ${filePaths.length} files to queue');

    final accepted = <QueuedFile>[];
    final skipped = <String>[];
    for (final filePath in filePaths) {
      try {
        if (await FileSystemEntity.type(filePath) != FileSystemEntityType.file) {
          skipped.add(path.basename(filePath));
          continue;
        }
        accepted.add(QueuedFile(filePath, path.basename(filePath), await File(filePath).length()));
      } on FileSystemException catch (e) {
        zprint('⚠️ Cannot queue $filePath: $e');
        skipped.add(path.basename(filePath));
      }
    }
    if (_disposed) return;
    if (skipped.isNotEmpty) onMessage?.call('Skipped (not a readable file): ${skipped.join(', ')}');
    if (accepted.isEmpty) return;

    if (!_isTransferring) {
      _isTransferring = true;
      _progress = 0;
      _speedMBps = 0;
      _transferComplete = false;
    }

    final startProcessing = _queue.isEmpty && !_processing;
    _queue.addAll(accepted);
    _notify();

    if (startProcessing) unawaited(_processQueue());
  }

  /// Cancels the running transfer and clears everything.
  void cancelAll() {
    final id = _activeTransferId;
    if (id != null) {
      _cancel(id);
      _activeTransferId = null;
    }

    _generation++;
    _isTransferring = false;
    _queue.clear();
    _completed.clear();
    _totalCompleted = 0;
    _notify();
    onMessage?.call('All transfers cancelled');
  }

  Future<void> _processQueue() async {
    if (_processing || _queue.isEmpty) return;
    _processing = true;
    final generation = _generation;
    bool stale() => generation != _generation || _disposed;

    while (_queue.isNotEmpty && !stale()) {
      final item = _queue.first;
      _currentFileName = item.name;
      _progress = 0;
      _speedMBps = 0;
      _transferComplete = false;
      _isTransferring = true;
      _preparing = true;
      _notify();

      final stopwatch = Stopwatch()..start();
      _throttle.reset();
      final transferId = _idGenerator(item.name);
      _activeTransferId = transferId;

      try {
        await _send(transferId, item.path, (totalSize, bytesSent) {
          if (stale()) return;
          _preparing = false;
          // Chunks arrive far faster than the UI needs; the final update is always delivered
          if (!_throttle.shouldEmit(force: bytesSent >= totalSize)) return;
          final seconds = stopwatch.elapsedMilliseconds / 1000;
          _progress = totalSize == 0 ? 100 : (bytesSent / totalSize) * 100;
          if (seconds > 0) _speedMBps = bytesSent / seconds / BYTES_PER_MB;
          _notify();
        });
        stopwatch.stop();

        if (stale()) break;
        _onSuccess(item, stopwatch.elapsed);
        await Future<void>.delayed(_pauseAfterSuccess);
      } catch (e, stackTrace) {
        zprint('❌ Error during file transfer: $e\n$stackTrace');
        if (stale()) break;
        _onFailure(item, e);
        await Future<void>.delayed(_pauseAfterFailure);
      } finally {
        _activeTransferId = null;
        _preparing = false;
      }
    }

    _processing = false;
    if (_queue.isEmpty) _isTransferring = false;
    _notify();
    // Files added after a cancel while this loop was still finishing need a new loop
    if (_queue.isNotEmpty && !_disposed) unawaited(_processQueue());
  }

  void _onSuccess(QueuedFile item, Duration elapsed) {
    final seconds = elapsed.inMilliseconds / 1000;
    final speed = seconds > 0 ? item.size / seconds / BYTES_PER_MB : 0.0;

    _progress = 100;
    _transferComplete = true;
    _speedMBps = speed;
    item.isCompleted = true;
    _totalCompleted++;
    _queue.removeFirst();
    _completed.add(item);
    _notify();

    onMessage?.call(
        'File sent successfully (${formatBytes(item.size)} in ${seconds.toStringAsFixed(1)}s, ${speed.toStringAsFixed(2)} MB/s)');
  }

  void _onFailure(QueuedFile item, Object error) {
    item.isFailed = true;
    item.errorMessage = error.toString();
    _queue.removeFirst();
    _completed.add(item);
    _notify();
    onMessage?.call('Error sending ${item.name}: $error');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final id = _activeTransferId;
    if (id != null) _cancel(id);
    super.dispose();
  }
}
