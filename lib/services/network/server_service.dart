import 'dart:async';
import 'dart:io';

import 'package:woxxy/funcs/debug.dart';

// Callback function type for handling newly accepted socket connections
typedef ConnectionHandlerCallback = Future<void> Function(Socket socket);

class ServerService {
  final int port;
  final ConnectionHandlerCallback connectionHandler;

  ServerSocket? _server;

  ServerService({
    required this.port,
    required this.connectionHandler,
  });

  Future<void> start() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      zprint('✅ Server started successfully on port $port');
      _server!.listen(
        (socket) {
          // Delegate handling to the provided callback
          connectionHandler(socket).catchError((e, s) {
            // Catch errors from the handler itself to prevent crashing the server loop
            zprint('❌ Error in connection handler for ${socket.remoteAddress.address}: $e\n$s');
            try {
              socket.destroy(); // Ensure socket is closed if handler fails badly
            } catch (_) {}
          });
        },
        onError: (e, s) {
          zprint('❌ Server socket error: $e\n$s');
          // Consider recovery or logging strategy
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
