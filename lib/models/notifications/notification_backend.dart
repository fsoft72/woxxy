/// Called when the user clicks a notification; [payload] is the value given to [NotificationBackend.show].
typedef NotificationClickHandler = void Function(String? payload);

/// One platform specific way of showing system notifications.
abstract class NotificationBackend {
  /// Prepares the platform (channels, permissions, app identity). Returns true when notifications can be shown.
  /// [onClick] must be called whenever the user clicks a notification shown by this backend.
  Future<bool> init(NotificationClickHandler onClick);

  /// Shows a notification. [id] is unique per notification so a new one does not replace the previous one.
  Future<void> show({required int id, required String title, required String body, String? payload});
}
