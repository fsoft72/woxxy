// ignore_for_file: constant_identifier_names

/// Width of the main window; it is locked, only the height can be changed
const double WINDOW_WIDTH = 540;

/// Height of the main window when the app starts
const double WINDOW_HEIGHT = 960;

/// Smallest height the user can give to the main window
const double WINDOW_MIN_HEIGHT = 600;

/// Largest height the user can give to the main window
const double WINDOW_MAX_HEIGHT = 4096;

/// Pause after the old tray icon was destroyed, before the new one is created
const Duration TRAY_RESET_DELAY = Duration(milliseconds: 100);

/// Pause between the tray setup steps on Windows (without it the context menu does not work)
const Duration WINDOWS_TRAY_STEP_DELAY = Duration(milliseconds: 200);

/// Radius of the profile picture in the settings screen
const double PROFILE_AVATAR_RADIUS = 50;
