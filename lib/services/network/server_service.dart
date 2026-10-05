import 'dart:async';
import 'dart:io';

import 'package:woxxy/config/network_constants.dart';
import 'package:woxxy/funcs/debug.dart';

// Callback function type for handling newly accepted socket connections
typedef ConnectionHandlerCallback = Future<void> Function(Socket socket);

class ServerService {
  final int port;
  final ConnectionHandlerCallback connectionHandler;

  /// Connections beyond this number are refused until a running one ends.
  final int maxConnections;

  ServerSocket? _server;
  int _activeConnections = 0;

  /// Port the server is really listening on (differs from [port] when that is 0), null when stopped.
  int? get boundPort => _server?.port;

  /// Number of connections currently being handled.
  int get activeConnections => _activeConnections;

  ServerService({
    required this.port,
    required this.connectionHandler,
    this.maxConnections = MAX_CONCURRENT_CONNECTIONS,
  });

  Future<void> start() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      zprint('✅ Server started successfully on port $port');
      _server!.listen(
        (socket) {
          if (_activeConnections >= maxConnections) {
            zprint('🚫 Too many connections ($maxConnections). Refusing ${socket.remoteAddress.address}.');
            socket.destroy();
            return;
          }
          _activeConnections++;
          // Delegate handling to the provided callback
          connectionHandler(socket).catchError((e, s) {
            // Catch errors from the handler itself to prevent crashing the server loop
            zprint('❌ Error in connection handler for ${socket.remoteAddress.address}: $e\n$s');
            try {
              socket.destroy(); // Ensure socket is closed if handler fails badly
            } catch (_) {}
          }).whenComplete(() => _activeConnections--);
        },
        onError: (e, s) {
          zprint('❌ Server socket error: $e\n$s');
        },
        onDone: () {
          zprint('ℹ️ Server socket closed.');
          _server = null; // Mark as closed
        },
      );
    } catch (e, s) {
      zprint('❌ FATAL: Could not bind server socket to port $port: $e\n$s');
      // This is critical, potentially notify user or stop the app part
      await dispose(); // Clean up if start fails
      throw Exception("Failed to start listening server: $e");
    }
  }

  Future<void> dispose() async {
    zprint('🛑 Disposing ServerService...');
    try {
      await _server?.close();
      _server = null;
    } catch (e) {
      zprint('⚠️ Error closing server socket: $e');
    }
    zprint('✅ ServerService disposed');
  }
}
