// ignore_for_file: avoid_print

void zprint(String message) {
  // only print messages in debug mode
  assert(() {
    print(message);
    return true;
  }());
}
