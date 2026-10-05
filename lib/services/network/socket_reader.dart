import 'dart:async';
import 'dart:typed_data';

/// Reads the bytes a peer sends back on a socket while the caller mostly writes to it.
///
/// A [Socket] can be listened to only once, so one reader owns the subscription for the whole
/// transfer and hands out the bytes on demand (ready signal first, final result later).
class SocketReader {
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  late final StreamSubscription<Uint8List> _subscription;
  Completer<void>? _waiter;
  Object? _error;
  bool _closed = false;

  /// Starts listening to [stream]; bytes are kept until they are read.
  SocketReader(Stream<Uint8List> stream) {
    _subscription = stream.listen(
      (data) {
        _buffer.add(data);
        _wake();
      },
      onError: (Object error) {
        _error = error;
        _closed = true;
        _wake();
      },
      onDone: () {
        _closed = true;
        _wake();
      },
      cancelOnError: true,
    );
  }

  /// True once the peer closed the connection (or it failed) and no more bytes will arrive.
  bool get isClosed => _closed;

  void _wake() {
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  /// Waits until [count] bytes are available, the connection closed or [timeout] passed, and
  /// returns at most [count] of the bytes received so far (fewer means closed or timed out;
  /// check [isClosed]). Throws the socket error if the connection failed with nothing to read.
  Future<Uint8List> read(int count, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_buffer.length < count && !_closed) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) break;
      final waiter = _waiter = Completer<void>();
      await waiter.future.timeout(left, onTimeout: () {});
    }
    if (_buffer.isEmpty && _error != null) throw _error!;

    final all = _buffer.takeBytes();
    if (all.length > count) _buffer.add(all.sublist(count));
    return all.length > count ? all.sublist(0, count) : all;
  }

  /// Stops listening. Does not close the socket.
  Future<void> dispose() => _subscription.cancel();
}
