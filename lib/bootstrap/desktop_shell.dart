// ignore_for_file: constant_identifier_names

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:woxxy/funcs/bundled_assets.dart';
import 'package:woxxy/funcs/debug.dart';

/// Window and system tray setup for the desktop platforms.
class DesktopShell {
  static const String _TOOLTIP = 'Woxxy';
  static const String _ICON_PNG = 'assets/icons/head.png';
  static const String _ICON_ICO = 'assets/icons/head.ico';

  /// True on Windows, Linux and macOS.
  static bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Configures the window (fixed width, resizable height), the tray icon and its menu, then shows the window.
  /// [onQuit] runs when the user picks "Quit" in the tray menu, before the process exits.
  /// Does nothing on mobile platforms.
  static Future<void> init({Future<void> Function()? onQuit}) async {
    if (!isDesktop) return;

    await _setupWindow();
    if (!Platform.isMacOS) await _setWindowIcon();
    await windowManager.waitUntilReadyToShow();
    await _setupTrayAndShow(onQuit);
  }

  /// Size limits, title and close behavior of the main window.
  static Future<void> _setupWindow() async {
    await windowManager.ensureInitialized();

    const windowSize = Size(540, 960);
    const minSize = Size(540, 600);
    const maxSize = Size(540, 4096);

    // Width is locked, only height is resizable
    await windowManager.setSize(windowSize);
    await windowManager.setMinimumSize(minSize);
    await windowManager.setMaximumSize(maxSize);
    await windowManager.center();
    await windowManager.setTitle('Woxxy');
    await windowManager.setPreventClose(true); // Ensure window hides on close
  }

  /// Sets the window icon from the bundled asset, falling back to an absolute path.
  static Future<void> _setWindowIcon() async {
    try {
      await windowManager.setIcon(_ICON_PNG);
    } catch (e) {
      zprint("❌ Failed to set window icon using asset path: $e");
      try {
        final bundledIcon = bundledAssetPath(_ICON_PNG);
        if (bundledIcon != null) {
          await windowManager.setIcon(bundledIcon);
        } else {
          zprint("⚠️ Icon not found in the app bundle either: $_ICON_PNG");
        }
      } catch (e2) {
        zprint("❌ Failed to set window icon using absolute path: $e2");
      }
    }
  }

  /// Creates the tray icon and menu, then shows the window (also when the tray fails).
  static Future<void> _setupTrayAndShow(Future<void> Function()? onQuit) async {
    try {
      final iconPath = await _resolveTrayIconPath();
      zprint("🔧 Using tray icon path: $iconPath");

      await trayManager.destroy(); // Ensure clean state
      await Future.delayed(const Duration(milliseconds: 100));

      final menu = Menu(items: [
        MenuItem(
          label: 'Open',
          onClick: (menuItem) async {
            await windowManager.show();
            await windowManager.focus();
          },
        ),
        MenuItem.separator(),
        MenuItem(
          label: 'Quit',
          onClick: (menuItem) async {
            zprint("🛑 Quit requested from tray menu.");
            try {
              await onQuit?.call();
            } catch (e) {
              zprint('⚠️ Error while shutting down: $e');
            }
            await windowManager.destroy(); // Close window properly
            exit(0);
          },
        ),
      ]);

      await _applyTray(iconPath, menu);
      zprint("✅ Tray setup complete.");
    } catch (e) {
      zprint('❌ Error setting up tray: $e');
    }

    await windowManager.show();
    await windowManager.focus();
  }

  /// Windows prefers .ico (falling back to .png), the other platforms use the .png asset.
  static Future<String> _resolveTrayIconPath() async {
    if (!Platform.isWindows) return _ICON_PNG; // The tray plugin resolves Flutter asset paths itself

    final icoPath = bundledAssetPath(_ICON_ICO);
    if (icoPath != null) return icoPath;

    zprint("⚠️ $_ICON_ICO not found in the app bundle, falling back to PNG.");
    final pngPath = bundledAssetPath(_ICON_PNG);
    if (pngPath == null) zprint("❌ Fallback $_ICON_PNG also not found in the app bundle");
    return pngPath ?? _ICON_PNG;
  }

  /// Applies icon, tooltip and menu in the order each platform tolerates.
  static Future<void> _applyTray(String iconPath, Menu menu) async {
    if (Platform.isWindows) {
      // Small delays between steps avoid context menu issues on Windows
      await trayManager.setIcon(iconPath);
      await Future.delayed(const Duration(milliseconds: 200));
      await trayManager.setToolTip(_TOOLTIP);
      await Future.delayed(const Duration(milliseconds: 200));
      await trayManager.setContextMenu(menu);
    } else if (Platform.isLinux) {
      // Everything at once on Linux avoids DBus menu issues
      await trayManager.setIcon(iconPath);
      await trayManager.setContextMenu(menu);
      await trayManager.setToolTip(_TOOLTIP);
    } else {
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip(_TOOLTIP);
      await trayManager.setContextMenu(menu);
    }
  }
}
