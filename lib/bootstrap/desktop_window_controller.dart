import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:woxxy/funcs/debug.dart';

import 'desktop_shell.dart';

/// The window and tray calls the controller needs; replaceable in tests.
abstract class DesktopWindow {
  Future<void> hide();
  Future<bool> isVisible();
  Future<void> show();
  Future<void> focus();
  Future<void> popUpTrayMenu();
}

/// [DesktopWindow] backed by the window_manager and tray_manager plugins.
class PluginDesktopWindow implements DesktopWindow {
  @override
  Future<void> hide() => windowManager.hide();

  @override
  Future<bool> isVisible() => windowManager.isVisible();

  @override
  Future<void> show() => windowManager.show();

  @override
  Future<void> focus() => windowManager.focus();

  @override
  Future<void> popUpTrayMenu() => trayManager.popUpContextMenu();
}

/// Reacts to the window close button and to clicks on the tray icon: the app lives in the tray,
/// so closing only hides the window. Created once in `main()`, for the whole life of the app.
class DesktopWindowController with TrayListener, WindowListener {
  final DesktopWindow _window;

  /// [window] defaults to the real plugins.
  DesktopWindowController({DesktopWindow? window}) : _window = window ?? PluginDesktopWindow();

  /// Starts listening. Does nothing on mobile platforms, which have neither window nor tray.
  void attach() {
    if (!DesktopShell.isDesktop) return;
    trayManager.addListener(this);
    windowManager.addListener(this);
  }

  /// Stops listening.
  void detach() {
    if (!DesktopShell.isDesktop) return;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
  }

  @override
  void onWindowClose() async {
    zprint('🔒 Window close requested, hiding window.');
    await _window.hide();
  }

  @override
  void onTrayIconMouseDown() async {
    zprint('🖱️ Tray icon clicked (left).');
    if (!await _window.isVisible()) await _window.show();
    await _window.focus();
  }

  // Right-click must open the menu explicitly (needed on Windows and Linux)
  @override
  void onTrayIconRightMouseDown() {
    zprint('🖱️ Tray icon clicked (right).');
    _window.popUpTrayMenu();
  }
}
