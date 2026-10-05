// ignore_for_file: constant_identifier_names

/// Default minimum time between two UI progress updates.
const Duration DEFAULT_PROGRESS_INTERVAL = Duration(milliseconds: 100);

/// Limits how often a high frequency event (such as per-chunk progress) reaches the UI.
class ProgressThrottle {
  final Duration interval;
  final DateTime Function() _now;
  DateTime? _lastEmit;

  /// Creates a throttle; [clock] is injectable for tests.
  ProgressThrottle({this.interval = DEFAULT_PROGRESS_INTERVAL, DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  /// Returns true when an update should be delivered now. The first call and any call with
  /// [force] (for example the final 100% update) always pass.
  bool shouldEmit({bool force = false}) {
    final now = _now();
    final last = _lastEmit;
    if (!force && last != null && now.difference(last) < interval) return false;
    _lastEmit = now;
    return true;
  }

  /// Forgets the last emission so the next call passes (use when a new transfer starts).
  void reset() => _lastEmit = null;
}
