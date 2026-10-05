import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:woxxy/funcs/debug.dart';

import '../models/history.dart';

/// Persists [FileHistory] in SharedPreferences.
class HistoryRepository {
  static const String _historyKey = 'file_history';

  /// Loads the saved history (empty when nothing is saved or the data is unreadable).
  Future<FileHistory> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return FileHistory();

    try {
      return FileHistory.fromJson(json.decode(raw) as List<dynamic>);
    } catch (e) {
      zprint('⚠️ Could not read saved history, starting empty: $e');
      return FileHistory();
    }
  }

  /// Saves [history] now.
  Future<void> save(FileHistory history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey, json.encode(history.toJson()));
  }

  Future<void>? _saveLoop;
  bool _dirty = false;

  /// Saves [history] every time it changes. Returns a function that stops saving.
  ///
  /// Writes never overlap: while one is running, further changes only mark the history as dirty
  /// and one more write with the latest state follows. A failing write is logged, not thrown.
  /// [flush] waits for the writes that are still pending.
  void Function() autoSave(FileHistory history) {
    void listener() {
      _dirty = true;
      _saveLoop ??= _saveWhileDirty(history).whenComplete(() => _saveLoop = null);
    }

    history.addListener(listener);
    return () => history.removeListener(listener);
  }

  Future<void> _saveWhileDirty(FileHistory history) async {
    while (_dirty) {
      _dirty = false;
      try {
        await save(history);
      } catch (e, s) {
        zprint('❌ Could not save the history: $e\n$s');
      }
    }
  }

  /// Completes when every change made so far has been written (or failed to be written).
  /// Call it before the app exits.
  Future<void> flush() async {
    while (_saveLoop != null) {
      await _saveLoop;
    }
  }
}
