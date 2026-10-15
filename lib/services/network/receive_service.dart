import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:woxxy/funcs/debug.dart';
import '../../config/network_constants.dart';
import '../../config/transfer_constants.dart';
import '../../models/avatars.dart';
import '../../models/file_received_event.dart';
import '../../models/file_transfer_manager.dart';
import '../../models/transfer_metadata.dart';
import 'transfer_protocol.dart';

/// Accepts incoming transfer connections: user files are written to the download folder through
/// [FileTransferManager], avatars are collected in memory and handed to the [AvatarStore].
class ReceiveService {
  final FileTransferManager fileTransferManager;
  final AvatarStore avatarStore;

  // Optional callback to notify the facade/UI about successfully received files
  final void Function(FileReceivedEvent event)? onFileReceivedCallback;

  /// A connection that sends nothing for this long is aborted and its partial file removed.
  final Duration idleTimeout;

  /// Sockets of the transfers being received right now, destroyed by [dispose].
  final Set<Socket> _activeSockets = {};

  ReceiveService({
    required this.fileTransferManager,
    required this.avatarStore,
    this.onFileReceivedCallback,
    this.idleTimeout = RECEIVE_IDLE_TIMEOUT,
  });

  /// Connection handler passed to ServerService.
  ///
  /// Chunks are consumed one at a time through a [StreamIterator], so a slow disk write or the
  /// ready-signal flush applies backpressure instead of letting events interleave.
  Future<void> handleNewConnection(Socket socket) async {
    final sourceIp = socket.remoteAddress.address;
    zprint('📥 New connection from $sourceIp:${socket.remotePort}');
    final stopwatch = Stopwatch()..start();
    _activeSockets.add(socket);

    // Configure socket for better Windows compatibility
    socket.setOption(SocketOption.tcpNoDelay, true);

    final decoder = MetadataFrameDecoder();
    // A stalled sender raises a TimeoutException, handled like any other transfer error
    final iterator = StreamIterator<Uint8List>(socket.timeout(idleTimeout));
    _IncomingTransfer? incoming; // Set once metadata is accepted
    var receivedBytes = 0;
    var dataExpected = 0;
    bool? outcome; // Reported to the sender; stays null when no transfer was accepted

    Future<void> receive(Uint8List data) async {
      if (data.isEmpty) return;
      if (receivedBytes + data.length > dataExpected) {
        throw ProtocolException('Peer sent more data than the declared $dataExpected bytes');
      }
      await incoming!.write(data);
      receivedBytes += data.length;
    }

    try {
      while (await iterator.moveNext()) {
        if (incoming != null) {
          await receive(iterator.current);
          continue;
        }

        final frame = decoder.add(iterator.current);
        if (frame == null) continue; // Header not complete yet

        final info = TransferMetadata.fromJson(frame.metadata);
        incoming = await _acceptTransfer(socket, sourceIp, info);
        if (incoming == null) return; // Rejected, socket already destroyed

        dataExpected = info.size;
        await receive(frame.remainingData);
      }

      zprint('📊 Socket closed after ${stopwatch.elapsedMilliseconds}ms. Received $receivedBytes/$dataExpected bytes.');
      if (incoming == null) {
        zprint("ℹ️ Socket closed before any metadata was accepted.");
      } else if (receivedBytes < dataExpected) {
        zprint('⚠️ Transfer incomplete ($receivedBytes/$dataExpected). Cleaning up...');
        await incoming.abort();
        outcome = false;
      } else {
        outcome = await incoming.finish();
      }
    } catch (e, s) {
      zprint('❌ Error during transfer from $sourceIp: $e\n$s');
      if (incoming != null) {
        zprint("🧨 Cleaning up transfer due to error...");
        await incoming.abort();
        outcome = false;
      }
    } finally {
      _activeSockets.remove(socket);
      await _sendResult(socket, outcome);
      await iterator.cancel();
      socket.destroy();
    }
  }

  /// Tells the sender whether the file was stored and verified. Best effort: the sender may be
  /// gone, and older senders do not read it.
  Future<void> _sendResult(Socket socket, bool? outcome) async {
    if (outcome == null) return;
    try {
      socket.add([outcome ? RESULT_OK : RESULT_FAILED]);
      await socket.flush();
    } catch (e) {
      zprint('ℹ️ Could not send the result to the sender: $e');
    }
  }

  /// Checks the header, prepares where the bytes go and sends the ready signal.
  /// Returns null if the transfer was rejected (the socket is then destroyed).
  /// A received avatar belongs to [sourceIp], the address the connection really came from, never
  /// to an address written in the metadata (any host could claim to be another peer).
  Future<_IncomingTransfer?> _acceptTransfer(Socket socket, String sourceIp, TransferMetadata info) async {
    zprint('📄 Received metadata: $info');

    final maxSize = info.isAvatar ? MAX_AVATAR_SIZE_BYTES : MAX_TRANSFER_SIZE_BYTES;
    if (info.size < 0 || info.size > maxSize) {
      zprint('❌ Rejecting transfer: declared size ${info.size} is outside 0..$maxSize.');
      socket.destroy();
      return null;
    }

    final _IncomingTransfer incoming;
    if (info.isAvatar) {
      incoming = _IncomingAvatar(info, sourceIp, avatarStore);
    } else {
      final key = await _addFileTransfer(sourceIp, info);
      if (key == null) {
        zprint("❌ Failed to add transfer for ${info.name} from $sourceIp. Closing connection.");
        socket.destroy();
        return null;
      }
      incoming = _IncomingFile(key, fileTransferManager, onFileReceivedCallback);
    }

    // Ready signal for better Windows compatibility
    try {
      socket.add(READY_SIGNAL);
      await socket.flush();
      zprint("📡 Ready signal sent to sender");
    } catch (e) {
      zprint("⚠️ Failed to send ready signal: $e");
    }
    return incoming;
  }

  /// Registers a user file with the manager. Returns its key, or null when it could not be created.
  Future<String?> _addFileTransfer(String sourceIp, TransferMetadata info) async {
    // Key by transfer id so parallel files from one IP never collide
    final remoteTransferId = info.transferId;
    final key = (remoteTransferId != null && remoteTransferId.isNotEmpty)
        ? '$sourceIp#$remoteTransferId'
        : '$sourceIp#${DateTime.now().microsecondsSinceEpoch}';
    return await fileTransferManager.add(key, info, sourceIp: sourceIp) ? key : null;
  }

  Future<void> dispose() async {
    zprint('🛑 Disposing ReceiveService...');
    // Destroying the socket ends handleNewConnection, which cleans up the partial file
    for (final socket in _activeSockets.toList()) {
      socket.destroy();
    }
    zprint('✅ ReceiveService disposed');
  }
}

/// Where the bytes of one accepted transfer go.
abstract class _IncomingTransfer {
  /// Stores a chunk; throws when it cannot be stored.
  Future<void> write(Uint8List data);

  /// All declared bytes arrived: verifies and delivers them. Returns true on success.
  Future<bool> finish();

  /// The transfer failed or ended early: drops what was received.
  Future<void> abort();
}

/// A user file written to the download folder.
class _IncomingFile implements _IncomingTransfer {
  final String key;
  final FileTransferManager manager;
  final void Function(FileReceivedEvent event)? onReceived;

  _IncomingFile(this.key, this.manager, this.onReceived);

  @override
  Future<void> write(Uint8List data) async {
    // A failed write (full disk, folder gone) aborts the transfer
    if (await manager.write(key, data)) return;
    throw FileSystemException('Could not write received data for transfer $key');
  }

  @override
  Future<bool> finish() async {
    final transfer = manager[key]!;
    if (!await manager.end(key)) {
      zprint('❌ File transfer finalization failed (end() returned false).');
      return false;
    }
    zprint('✅ File transfer finalized successfully.');
    onReceived?.call(FileReceivedEvent(
      filePath: transfer.destinationFilename,
      senderUsername: transfer.senderUsername,
      fileSize: transfer.size,
      speedMBps: transfer.getSpeedMBps(),
    ));
    return true;
  }

  @override
  Future<void> abort() => manager.handleSocketClosure(key);
}

/// An avatar (at most [MAX_AVATAR_SIZE_BYTES]) collected in memory and stored for [sourceIp].
class _IncomingAvatar implements _IncomingTransfer {
  final TransferMetadata info;
  final String sourceIp;
  final AvatarStore store;
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  _IncomingAvatar(this.info, this.sourceIp, this.store);

  @override
  Future<void> write(Uint8List data) async => _bytes.add(data);

  @override
  Future<bool> finish() async {
    final bytes = _bytes.takeBytes();
    final hash = md5.convert(bytes).toString();
    final expected = info.md5Checksum;
    if (expected != null && expected.isNotEmpty && expected != LEGACY_CHECKSUM_ERROR && expected != hash) {
      zprint('❌ Avatar from $sourceIp does not match its checksum.');
      return false;
    }

    try {
      // Decoding in the store rejects anything that is not a valid image
      await store.setAvatar(sourceIp, bytes, hash: hash);
      zprint('✅ Avatar stored for $sourceIp (${bytes.length} bytes)');
    } catch (e) {
      zprint('❌ Error processing received avatar for $sourceIp: $e');
    }
    return true;
  }

  @override
  Future<void> abort() async => _bytes.clear();
}
