// ignore_for_file: avoid_print

void zprint(String message) {
  // print only in debug mode

  if (const bool.fromEnvironment('dart.vm.product')) {
    return;
  }

  print("[Woxxy] $message");
}
