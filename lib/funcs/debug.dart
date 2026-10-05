// ignore_for_file: avoid_print

/// Logging is on in debug and profile builds, off in release (product) builds.
/// Tests can flip it to check that disabled logging costs nothing.
bool zprintEnabled = !const bool.fromEnvironment('dart.vm.product');

/// Where log lines go; replaceable in tests.
void Function(String line) zprintSink = print;

/// Prints [message] with the Woxxy prefix when logging is enabled.
///
/// The argument is evaluated by the caller even in release builds, so use [zprintLazy] when
/// building the message is expensive (encoding JSON, joining large collections).
void zprint(String message) {
  if (!zprintEnabled) return;
  zprintSink("[Woxxy] $message");
}

/// Like [zprint], but [buildMessage] only runs when logging is enabled.
void zprintLazy(String Function() buildMessage) {
  if (!zprintEnabled) return;
  zprintSink("[Woxxy] ${buildMessage()}");
}
