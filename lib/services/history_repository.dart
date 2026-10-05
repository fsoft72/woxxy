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

  /// Saves [history] every time it changes. Returns a function that stops saving.
  void Function() autoSave(FileHistory history) {
    void listener() => save(history);
    history.addListener(listener);
    return () => history.removeListener(listener);
  }
}
