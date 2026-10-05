# Changes Log

## Make the NetworkService collaborators injectable

`NetworkService` accepts the identity, send, server and discovery services (the IP lookup moved to `LocalIpResolver` earlier) and the avatar hashing moved to `md5OfPathOrNull` in `funcs/hashing.dart`. Tests: `test/network_service_injection_test.dart`, `test/hashing_test.dart`.

## Unify the close and verify logic of FileTransfer

`FileTransfer` closes the sink in one private method used by both paths. `closeOnSocketClosure` now always deletes the partial file (the old 'checksum matched, keep it' branch could never lead to a recorded file), and `end` is a flat close, verify, delete sequence. Test updated in `test/file_transfer_md5_test.dart`.

## Stop rebuilding the peer list when an avatar arrives

`ReceiveService` no longer depends on `PeerManager`: a received avatar updates only the per-peer `AvatarStore` notifier, and `notifyPeersUpdated` was removed. Test in `test/transfer_loopback_test.dart`.

## Keep the peer detail page in sync with the peer list

`PeerDetailPage` follows `peerStream`: sends use the latest address data of the peer, and a peer that left shows an offline warning and disables the drop zone and Browse button (`SendDropZone.enabled`). `NetworkService` accepts an injected `PeerManager`. Tests: `test/peer_details_test.dart`.

## Choose the local IP with a resolver that skips virtual adapters

New `LocalIpResolver` (moved out of `NetworkService`): a failing Wi-Fi lookup no longer skips the interface search, and `pickLocalAddress` prefers private addresses of real adapters over Docker, VM and VPN ones. Tests: `test/local_ip_resolver_test.dart`.

## Pass the user to NetworkService.start

`NetworkService.start(user)` takes the current user from the caller, so settings are no longer loaded a second time and `NetworkService` lost its `SettingsService` dependency. `HomePage` passes its current user (also on retry). Test in `test/network_start_test.dart`.

## Do not hash the avatar again on every send

`sendAvatar` reuses the hash announced in discovery when it belongs to the same file, and `NetworkService.setProfileImagePath` ignores an unchanged path, so saving a new username no longer rehashes the picture. Tests: `test/avatar_hash_reuse_test.dart`.

## Use a generation token in the send queue

`SendQueueController` replaces the shared cancelled flag with a generation number bumped by `cancelAll`. A cancelled send that rejects late is ignored and can no longer fail the first of the files added afterwards; a new loop starts for them. Test in `test/send_queue_controller_test.dart`.

## Skip invalid paths when files are queued

`SendQueueController.addFiles` now checks every path first, skips folders and vanished files with a message, and only then touches the queue state, so the UI cannot get stuck. `_pickFiles` ignores null paths. Tests in `test/send_queue_controller_test.dart`.

## Receiver confirms each transfer with a result byte

After finalizing, the receiver sends one byte (`RESULT_OK` or `RESULT_FAILED`). The sender half-closes, waits up to 30 s for it and fails the send when the receiver reports a failure; a missing byte (older receiver) still counts as success. Tests: `test/transfer_result_test.dart` and the `result byte` group of `test/transfer_loopback_test.dart`.

## Fail fast when the receiver closes before the ready signal

A new `SocketReader` owns the single socket subscription of a send. A receiver that closes the connection now fails the send at once, a ready signal split in several chunks is buffered, and only a silent receiver still gets the file after the timeout. Tests: `test/ready_signal_test.dart`.

## Validate profile pictures before announcing them

ProfileImageStore.import now rejects pictures above 10 MB or 4096 px, the settings screen reports why, and NetworkService does not announce the hash of an oversized avatar, so peers no longer ask for an image nobody can send. Tests in `test/settings_test.dart`.

## Honor cancel while a send is being prepared

SendService tracks every transfer from the start of sendFile, so a cancel during hashing or connecting stops the send before any byte leaves. Test: `test/send_cancel_test.dart`.

## Regenerate OPTIMIZE.md with a new code analysis

All items of the previous list were done, so `OPTIMIZE.md` was rewritten from a fresh read of `lib/`. It has 4 High, 11 Medium and 8 Low items (the main ones: cancel is ignored while preparing a send, rejected avatars are re-requested forever, no result frame from the receiver, folders dropped on the queue). No code was changed.

### Files
- `OPTIMIZE.md`

## Guard the app version and drop the dangling env.dart symlink

The publish script already writes APP_VERSION from pubspec.yaml, so instead of adding a dependency a test now fails when version.dart and pubspec.yaml differ. The tracked lib/config/env.dart symlink (target missing, already in .gitignore, unused by the code) was removed, with a test that no dangling link lives in lib.

### Files
- `lib/config/env.dart`
- `test/version_test.dart`

---

## Release avatar notifiers of removed peers

removeAvatar disposes and forgets the notifier of a peer when no widget listens to it (a watched notifier is kept so the widget still receives later updates). The unused getKeys debug method was removed. Added a test.

### Files
- `lib/models/avatars.dart`
- `test/avatar_store_test.dart`

---

## Use a stable hash for avatar colors

getAvatarColorForPeer uses an FNV-1a hash instead of String.hashCode, so a peer has the same color on every platform. Added a test with fixed expected colors.

### Files
- `lib/widgets/peer_avatar.dart`
- `test/avatar_store_test.dart`

---

## Remove logging from the peer list build

The StreamBuilder of the peer list no longer calls zprint on every rebuild. Added a test that building the list writes nothing to the log.

### Files
- `lib/screens/home.dart`
- `test/home_content_test.dart`

---

## Make the current user non-nullable in HomePage

_currentUser is always the initial user, so it is now non-nullable and the unreachable null branches in _getScreens and build are gone. The screen list is still built on each build because SettingsScreen must receive the updated user (it is cheap). HomePage needs tray and window plugins, so there is no widget test for it: covered by analyzer and the existing suite.

### Files
- `lib/screens/home_page.dart`

---

## Remove outdated and noisy comments

Deleted comments that described history instead of the code (Removed userId, Removed _loadSettings, FIX notes, class end markers, 'Consider...' notes, import labels, commented out code). Comment-only change: analyzer clean and the full suite still passes.

### Files
- `lib/models/file_transfer.dart`
- `lib/models/file_transfer_manager.dart`
- `lib/models/peer_manager.dart`
- `lib/services/network/discovery_service.dart`
- `lib/services/network/server_service.dart`
- `lib/services/network/receive_service.dart`
- `lib/screens/home_page.dart`
- `lib/services/network_service.dart`

---

## Use named parameters in FileTransfer.start

FileTransfer.start takes named parameters and no longer has the redundant key (sourceIp is required). FileTransferManager.add and the tests were updated; behavior is unchanged, the existing md5, filename and manager tests cover it.

### Files
- `lib/models/file_transfer.dart`
- `lib/models/file_transfer_manager.dart`
- `test/filename_test.dart`
- `test/file_transfer_md5_test.dart`
- `test/hashing_test.dart`

---

## Use formatBytes for every displayed size

HistoryScreen, the send success message and the avatar log lines use formatBytes instead of their own divisions by 1024 / BYTES_PER_MB. The send message now shows the speed as MB/s like the rest of the app. Tests assert the formatted sizes.

### Files
- `lib/screens/history.dart`
- `lib/services/send_queue_controller.dart`
- `lib/services/network/send_service.dart`
- `test/send_queue_controller_test.dart`
- `test/history_persistence_test.dart`
- `test/file_opener_test.dart`

---

## Split utils.dart and share the folder opener

utils.dart is split into ui_helpers (showSnackbar), file_opener (openFileLocation and the new shared openDirectory), format (formatBytes) and transfer_id (generateTransferId). NotificationManager no longer repeats the platform switch. The opener takes an injectable process runner. Added file_opener_test.

### Files
- `lib/funcs/utils.dart`
- `lib/funcs/ui_helpers.dart`
- `lib/funcs/file_opener.dart`
- `lib/funcs/format.dart`
- `lib/funcs/transfer_id.dart`
- `lib/models/notification_manager.dart`
- `lib/screens/history.dart`
- `lib/screens/home.dart`
- `lib/screens/peer_details.dart`
- `lib/screens/settings.dart`
- `lib/screens/home_page.dart`
- `lib/services/send_queue_controller.dart`
- `lib/widgets/send/queue_summary.dart`
- `test/file_opener_test.dart`
- `test/send_queue_controller_test.dart`
- `test/constants_test.dart`

---

## Use DEFAULT_USERNAME everywhere

The five 'WoxxyUser' literals were already replaced by DEFAULT_USERNAME with LocalIdentity; SettingsService now uses it too, so a first run gets the same name everywhere instead of 'User'. Added a test.

### Files
- `lib/services/settings_service.dart`
- `test/settings_service_test.dart`

---

## Await settings saves, report failures and write only changes

HomePage._updateUser awaits saveSettings and shows a snackbar when it fails. SettingsService.saveSettings writes only the values that differ from the stored ones. Added settings_service_test.

### Files
- `lib/screens/home_page.dart`
- `lib/services/settings_service.dart`
- `test/settings_service_test.dart`

---

## Check the download folder result and mounted in Settings

Choosing a download folder now checks mounted after the await and reports a folder that cannot be created (snackbar) instead of saving it. The picker is injectable (directoryPicker). Added widget tests.

### Files
- `lib/screens/settings.dart`
- `test/settings_test.dart`

---

## Pass the avatar request function to PeerManager at construction

PeerManager takes requestAvatar in its constructor, so the setRequestAvatarCallback setter and the construction order dependency are gone (NetworkService passes a late bound lambda). SendAvatarCallback now matches SendService.sendAvatar (Future<bool>). Existing tests moved to the constructor argument.

### Files
- `lib/models/peer_manager.dart`
- `lib/services/network_service.dart`
- `lib/services/network/discovery_service.dart`
- `test/discovery_protocol_test.dart`
- `test/peer_manager_test.dart`
- `test/avatar_store_test.dart`

---

## Serialize history saves and log failures

HistoryRepository.autoSave runs one write at a time, merges changes made during a write into one more write with the latest state, and logs failures instead of leaving unhandled async errors. Added tests.

### Files
- `lib/services/history_repository.dart`
- `test/history_persistence_test.dart`

---

## Limit the decoded size of received avatars

AvatarStore reads the declared size first (ImageDescriptor), rejects sides above MAX_AVATAR_SIDE_PIXELS and decodes at most AVATAR_DECODE_SIDE_PIXELS on the longest side. Added tests with real PNGs.

### Files
- `lib/models/avatars.dart`
- `lib/config/transfer_constants.dart`
- `test/avatar_store_test.dart`

---

## Stop in-flight receives on dispose

ReceiveService tracks its active sockets and destroys them in dispose, which closes the file sinks and removes the partial files. Added a test.

### Files
- `lib/services/network/receive_service.dart`
- `test/server_limits_test.dart`

---

## Remove the 100 ms zero-byte heuristic

The special case for 'zero bytes in under 100 ms' did exactly what the next incomplete-transfer check does, so it was removed together with its magic number. Added a test for a sender that closes right after the header.

### Files
- `lib/services/network/receive_service.dart`
- `test/server_limits_test.dart`

---

## Share one md5OfFile helper and drop the checksum sentinel

New funcs/hashing.dart md5OfFile replaces the Completer based hashing in SendService and the inline hashing in NetworkService. A file that cannot be hashed is now announced with a null checksum; the receiver still accepts the legacy 'CHECKSUM_ERROR' value (LEGACY_CHECKSUM_ERROR). Added tests.

### Files
- `lib/funcs/hashing.dart`
- `lib/services/network/send_service.dart`
- `lib/services/network_service.dart`
- `lib/models/file_transfer.dart`
- `lib/config/transfer_constants.dart`
- `test/hashing_test.dart`

---

## Show a Preparing state while the file is hashed

The protocol keeps the checksum in the header (compatible with older peers), so instead of a trailer the queue now reports isPreparing until the first progress report and TransferProgressCard shows an indeterminate bar with 'Preparing...'. Added tests.

### Files
- `lib/widgets/send/transfer_progress_card.dart`
- `lib/services/send_queue_controller.dart`
- `lib/screens/peer_details.dart`
- `test/send_queue_controller_test.dart`

---

## Let the owner of AppServices dispose the network service

HomePage no longer disposes the NetworkService it does not own. AppServices.dispose stops the handler and the network service and runs from the tray Quit action (DesktopShell.init onQuit). Added a test.

### Files
- `lib/app_services.dart`
- `lib/main.dart`
- `lib/bootstrap/desktop_shell.dart`
- `lib/screens/home_page.dart`
- `test/app_services_test.dart`

---

## Move received-file handling out of HomePage

New ReceivedFilesHandler (history entry plus notification) is created in AppServices and started in main(), so it lives as long as the app and no file is lost when a screen is unmounted. HomePage no longer listens to onFileReceived. Added tests.

### Files
- `lib/services/received_files_handler.dart`
- `lib/app_services.dart`
- `lib/main.dart`
- `lib/screens/home_page.dart`
- `test/received_files_handler_test.dart`

---

## Share one LocalIdentity between the network services

New LocalIdentity holds the local IP, username, profile image and avatar hash. NetworkService, SendService and DiscoveryService share it, so the updateUserDetails fan-out is gone. Also adds DEFAULT_USERNAME. Tests updated, new local_identity_test.

### Files
- `lib/models/local_identity.dart`
- `lib/config/network_constants.dart`
- `lib/services/network_service.dart`
- `lib/services/network/send_service.dart`
- `lib/services/network/discovery_service.dart`
- `test/local_identity_test.dart`
- `test/discovery_protocol_test.dart`
- `test/send_backpressure_test.dart`
- `test/transfer_loopback_test.dart`

---

## Rate limit avatar requests per address

DiscoveryService answers an avatar request from the same address at most once per AVATAR_REQUEST_MIN_INTERVAL (injectable clock). Added a test.

### Files
- `lib/config/network_constants.dart`
- `lib/services/network/discovery_service.dart`
- `test/discovery_protocol_test.dart`

---

## Apply backpressure on disk writes

FileTransfer.write waits for fileSink.flush() once WRITE_FLUSH_THRESHOLD_BYTES (4 MiB) are buffered, so a slow disk throttles the sender through TCP instead of growing memory. Added a test.

### Files
- `lib/config/transfer_constants.dart`
- `lib/models/file_transfer.dart`
- `test/file_transfer_md5_test.dart`

---

## Abort receiving when a write fails

ReceiveService now checks the result of FileTransferManager.write and aborts the transfer (partial file removed) instead of waiting for the end to find a corrupt file. Added a test with a failing manager.

### Files
- `lib/services/network/receive_service.dart`
- `test/server_limits_test.dart`

---

## Limit connections and abort stalled receives

ServerService refuses connections above MAX_CONCURRENT_CONNECTIONS and ReceiveService aborts a transfer that sends nothing for RECEIVE_IDLE_TIMEOUT, cleaning the partial file. Added tests.

### Files
- `lib/config/network_constants.dart`
- `lib/services/network/server_service.dart`
- `lib/services/network/receive_service.dart`
- `test/server_limits_test.dart`

---

## Document the two Critical analysis items as not issues

The "receiver accepts files without consent" and "avatar owner from metadata" findings were reviewed and declared not problems (trusted LAN, automatic receive by design). They are kept in OPTIMIZE.md under "Not issues (by design)" and are not fixed.

### Files
- `OPTIMIZE.md`

---

## Make logging cheap in release builds

zprint is now switchable (zprintEnabled/zprintSink) and a new zprintLazy only builds its message when logging is enabled; the expensive calls (metadata JSON and maps) use it. No file calls print() directly any more. Added logging tests including a guard against direct print().

### Files
- `lib/funcs/debug.dart`
- `lib/services/network/send_service.dart`
- `lib/models/file_transfer.dart`
- `test/logging_test.dart`

---

## Centralize constants and style cleanups

Ports, discovery interval, ready-signal and connect timeouts, the avatar size cap and BYTES_PER_MB moved to config/network_constants.dart and transfer_constants.dart (no more literals in services). FileTransfer fields and parameters are camelCase (the lint ignore is gone), and generateTransferId now adds a counter and random part so ids cannot collide. withOpacity was already replaced in the extracted widgets. Added guard and uniqueness tests.

### Files
- `lib/config/network_constants.dart`
- `lib/config/transfer_constants.dart`
- `lib/funcs/utils.dart`
- `lib/models/file_transfer.dart`
- `lib/models/file_transfer_manager.dart`
- `lib/models/file_received_event.dart`
- `lib/screens/history.dart`
- `lib/services/network_service.dart`
- `lib/services/network/send_service.dart`
- `lib/services/network/discovery_service.dart`
- `lib/services/network/receive_service.dart`
- `lib/services/send_queue_controller.dart`
- `test/constants_test.dart`
- `test/filename_test.dart`
- `test/file_transfer_manager_test.dart`
- `test/file_transfer_md5_test.dart`

---

## Inject dependencies instead of singletons

FileTransferManager, AvatarStore and NotificationManager are plain classes now (no static instances), NetworkService receives its collaborators and a single SettingsService, and widgets get the AvatarStore/NotificationManager/FileTransferManager they need through constructors. main() builds everything once in AppServices.create and passes it to MyApp/HomePage. Tests build isolated instances (test/support/test_services.dart) and a guard test checks no singleton came back.

### Files
- `lib/app_services.dart`
- `lib/app.dart`
- `lib/main.dart`
- `lib/models/file_transfer_manager.dart`
- `lib/models/avatars.dart`
- `lib/models/notification_manager.dart`
- `lib/models/peer_manager.dart`
- `lib/services/network_service.dart`
- `lib/widgets/peer_avatar.dart`
- `lib/screens/home.dart`
- `lib/screens/home_page.dart`
- `lib/screens/peer_details.dart`
- `lib/screens/settings.dart`
- `test/support/test_services.dart`
- `test/dependency_injection_test.dart`
- `test/avatar_store_test.dart`
- `test/home_content_test.dart`
- `test/network_start_test.dart`
- `test/notification_manager_test.dart`
- `test/settings_test.dart`
- `test/transfer_loopback_test.dart`

---

## Refactor `NotificationManager` per platform

NotificationManager (387 lines of Platform.isX chains) is now a ~120 line coordinator over a NotificationBackend interface with one implementation per platform (Android, Windows, macOS, Linux) under models/notifications/. The Linux payload workaround lives in the Linux backend, the stray print/DEBUG output and commented-out code are gone, and all logging goes through zprint. Tests use a fake backend.

### Files
- `lib/models/notification_manager.dart`
- `lib/models/notifications/notification_backend.dart`
- `lib/models/notifications/android_notification_backend.dart`
- `lib/models/notifications/macos_notification_backend.dart`
- `lib/models/notifications/linux_notification_backend.dart`
- `lib/models/notifications/windows_notification_backend.dart`
- `lib/models/notifications/platform_notification_backend.dart`
- `test/notification_manager_test.dart`

---

## Break up `peer_details.dart`

The 635 line page is now 174 lines. Queue and transfer state moved to SendQueueController (a ChangeNotifier with injectable send/cancel functions, throttled progress, cancel and failure handling), the UI to TransferProgressCard, QueueSummary and SendDropZone widgets, and size formatting to a shared formatBytes (now with GB). The unused _progressSubscription and newFiles are gone. Added controller and widget tests.

### Files
- `lib/screens/peer_details.dart`
- `lib/services/send_queue_controller.dart`
- `lib/widgets/send/transfer_progress_card.dart`
- `lib/widgets/send/queue_summary.dart`
- `lib/widgets/send/send_drop_zone.dart`
- `lib/funcs/utils.dart`
- `test/send_queue_controller_test.dart`

---

## Split `main()` and fix the fatal error screen

main() shrank from ~190 to ~50 lines: window/tray setup moved to bootstrap/desktop_shell.dart (split into small methods), download folder resolution to bootstrap/download_path.dart (with fallback), MyApp to app.dart and HomePage to screens/home_page.dart. The fatal error handler now always calls runApp(InitErrorApp) (the old isRootWidgetAttached check was always false, so no error screen was ever shown). Added tests.

### Files
- `lib/main.dart`
- `lib/app.dart`
- `lib/screens/home_page.dart`
- `lib/bootstrap/desktop_shell.dart`
- `lib/bootstrap/download_path.dart`
- `lib/widgets/init_error_app.dart`
- `test/bootstrap_test.dart`

---

## Fix the settings screen behaviors

The username is validated per keystroke but saved/announced only after a 600 ms pause or on submit, and empty names are rejected with a message. SVG is no longer offered as a profile picture (peers cannot decode it) and legacy SVG paths render with SvgPicture.file. Picked pictures are copied into app storage by ProfileImageStore (new file name each time so the image cache never shows a stale picture). Added widget and unit tests.

### Files
- `lib/screens/settings.dart`
- `lib/services/profile_image_store.dart`
- `test/settings_test.dart`

---

## Fix `FileHistory` sorting, persistence and notifications

FileHistory is now a ChangeNotifier that keeps entries sorted on insert (no sort inside the getter), caps itself at 500 entries and tolerates corrupt saved data. A HistoryRepository persists it in SharedPreferences on every change and main() loads it before the first frame; HistoryScreen listens with ListenableBuilder instead of manual setState. Added history, persistence and widget tests.

### Files
- `lib/models/history.dart`
- `lib/services/history_repository.dart`
- `lib/screens/history.dart`
- `lib/main.dart`
- `test/file_history_test.dart`
- `test/history_persistence_test.dart`

---

## Keep tab state with `IndexedStack`

The three tabs are shown through a PersistentTabs (IndexedStack) widget, so switching tabs no longer destroys and re-creates HomeContent, HistoryScreen and SettingsScreen state. Added a widget test.

### Files
- `lib/widgets/persistent_tabs.dart`
- `lib/main.dart`
- `test/persistent_tabs_test.dart`

---

## Recover from discovery socket loss and IP changes

DiscoveryService re-binds automatically (with retries) when its socket closes or errors, can be restarted explicitly, announces immediately on start and broadcasts to both 255.255.255.255 and the local /24 address. A new IpMonitor re-resolves the local IP every 15 s; on change NetworkService updates the send/discovery services and restarts discovery. Added fake_async and loopback tests.

### Files
- `lib/services/network/discovery_service.dart`
- `lib/services/network/discovery_protocol.dart`
- `lib/services/network/ip_monitor.dart`
- `lib/services/network_service.dart`
- `test/ip_monitor_test.dart`
- `test/discovery_protocol_test.dart`

---

## Fix avatar cache correctness and rebuild cost

Peers now announce the MD5 of their avatar; PeerManager re-requests it when the cached hash differs (throttled to once per 30 s) and evicts it when the peer has none or leaves. AvatarStore disposes replaced images after a grace delay (no disposed-image crash), exposes a per-peer ValueListenable, and no longer logs on every miss. PeerAvatarWidget listens only to its own peer, so an update rebuilds one avatar instead of all.

### Files
- `lib/models/avatars.dart`
- `lib/models/peer.dart`
- `lib/models/peer_manager.dart`
- `lib/widgets/peer_avatar.dart`
- `lib/screens/home.dart`
- `lib/screens/peer_details.dart`
- `lib/services/network_service.dart`
- `lib/services/network/discovery_protocol.dart`
- `lib/services/network/discovery_service.dart`
- `lib/services/network/receive_service.dart`
- `test/avatar_store_test.dart`
- `test/peer_manager_test.dart`
- `test/discovery_protocol_test.dart`

---

## Fix `PeerManager` lifecycle and updates

PeerManager is no longer a global singleton (each NetworkService owns one, so disposing it cannot break a later instance), the avatar callback is optional, add/notify after dispose are ignored, announcements with a new name/port update the known peer, and the cleanup timer now runs at a third of the timeout. Clock and timeout are injectable; tests use fake_async.

### Files
- `lib/models/peer_manager.dart`
- `test/peer_manager_test.dart`
- `test/discovery_protocol_test.dart`

---

## Harden the receiver against hostile peers

The receiver rejects negative or oversized declared sizes (64 GiB files, 10 MB avatars) before creating any file and aborts a transfer, deleting the partial file, as soon as the peer sends more bytes than declared. Free-disk check and an accept prompt were intentionally not added (they need a plugin and a UX decision). Added hostile-sender loopback tests.

### Files
- `lib/config/transfer_constants.dart`
- `lib/services/network/receive_service.dart`
- `test/transfer_loopback_test.dart`

---

## Add automated tests

The project now has a test suite (flutter test): filename sanitization, metadata framing, incremental MD5, transfer manager, loopback send/receive, backpressure, discovery protocol, notifications, history and peer manager basics. PeerManager timeout tests land with the PeerManager rework, and fake_async was added as a dev dependency for them.

### Files
- `pubspec.yaml`
- `pubspec.lock`
- `test/transfer_protocol_test.dart`
- `test/file_history_test.dart`
- `test/peer_manager_test.dart`

---

## Make the discovery protocol robust

Discovery datagrams are now versioned UTF-8 JSON (discovery_protocol.dart) decoded into typed messages, so usernames with ':' or non-ASCII characters work and malformed or foreign datagrams are ignored. Note: this changes the wire format, so all peers on the LAN must run this version. Added protocol and DiscoveryService tests.

### Files
- `lib/services/network/discovery_protocol.dart`
- `lib/services/network/discovery_service.dart`
- `test/discovery_protocol_test.dart`

---

## Handle network start failure

NetworkService.start() now throws a NetworkStartException when no IP is found (instead of returning silently) and only stops discovery/server on failure so it can be retried. HomePage catches it and shows StartupErrorView with a Retry button instead of an endless spinner. IP resolution is injectable for tests.

### Files
- `lib/services/network_service.dart`
- `lib/widgets/startup_error_view.dart`
- `lib/main.dart`
- `test/network_start_test.dart`

---

## Replace the stringly-typed

The string stream and the dead '|' parser are gone (typed FileReceivedEvent introduced in the previous commit); both consumers now keep their StreamSubscription and cancel it in dispose, so HomeContent no longer leaks a listener (and duplicate snackbars) each time it is rebuilt. Added widget tests.

### Files
- `lib/services/network_service.dart`
- `lib/screens/home.dart`
- `lib/main.dart`
- `test/home_content_test.dart`

---

## Remove UI side effects from the `FileTransfer` model

FileTransfer.end() and FileTransferManager no longer touch NotificationManager or FileHistory. ReceiveService emits a typed FileReceivedEvent (path, sender, size, speed) through NetworkService.onFileReceived, and HomePage is the single consumer that records history and shows the notification. Added event assertions to the loopback test and a layering guard test.

### Files
- `lib/models/file_received_event.dart`
- `lib/models/file_transfer.dart`
- `lib/models/file_transfer_manager.dart`
- `lib/services/network/receive_service.dart`
- `lib/services/network_service.dart`
- `lib/main.dart`
- `lib/screens/home.dart`
- `test/transfer_loopback_test.dart`
- `test/layering_test.dart`

---

## Fix notification click on Linux and the fixed notification id

Linux now registers the same click handler as the other platforms (it only logged before), so clicking a file received notification opens the folder; every notification gets an incrementing id instead of always 0. Includes the previously uncommitted Linux payload workaround in this file. Added unit tests.

### Files
- `lib/models/notification_manager.dart`
- `lib/config/transfer_constants.dart`
- `test/notification_manager_test.dart`

---

## Throttle progress updates to the UI

Per-chunk progress callbacks are now filtered by a ProgressThrottle (100 ms, final update always forced) before reaching setState in PeerDetailPage. Added unit tests with an injected clock.

### Files
- `lib/funcs/throttle.dart`
- `lib/screens/peer_details.dart`
- `test/throttle_test.dart`

---

## Respect backpressure when sending

SendService streams the file with socket.addStream, so the file reader pauses while the socket buffer is full instead of queueing the whole file. A cancel that ends addStream silently is now detected and reported as an error. Added a stalled-receiver test.

### Files
- `lib/services/network/send_service.dart`
- `test/send_backpressure_test.dart`

---

## Do not buffer the whole received file in RAM for MD5

FileTransfer no longer keeps every received byte in memory: the MD5 is computed incrementally with a chunked conversion fed on each write. Added tests for matching/mismatching checksums and socket-closure behavior.

### Files
- `lib/models/file_transfer.dart`
- `test/file_transfer_md5_test.dart`
- `test/transfer_loopback_test.dart`

---

## Serialize the receive handler

ReceiveService now consumes the socket through a StreamIterator, so metadata parsing, transfer registration, the ready signal and data writes run strictly one at a time (no duplicate adds or out-of-order writes). Metadata framing moved to a reusable MetadataFrameDecoder/encodeMetadataFrame in transfer_protocol.dart (BytesBuilder instead of List<int>). Added loopback integration tests.

### Files
- `lib/config/transfer_constants.dart`
- `lib/services/network/transfer_protocol.dart`
- `lib/services/network/receive_service.dart`
- `lib/services/network/send_service.dart`
- `test/transfer_loopback_test.dart`

---

## Stop keying transfers by source IP only

Transfers are now keyed by the sender's transferId (ip#transferId); duplicate keys are rejected instead of overwritten, avatar files are written to a temp directory instead of the download folder, and unique destination paths are reserved atomically with an exclusive create to remove the exists/open race.

### Files
- `lib/models/file_transfer.dart`
- `lib/models/file_transfer_manager.dart`
- `lib/services/network/receive_service.dart`
- `test/file_transfer_manager_test.dart`

---

## Sanitize the remote filename

Remote filenames are reduced to a safe last path segment (both separators, control chars, length cap, fallback name) before the destination path is built, so a hostile sender cannot write outside the download folder. Added unit and FileTransfer tests.

### Files
- `lib/funcs/filename.dart`
- `lib/models/file_transfer.dart`
- `test/filename_test.dart`

---

## Code Optimization Analysis

Added `OPTIMIZE.md`, a prioritized checklist of 25 optimization, security and refactoring items found by reviewing the whole `lib/` tree. No application code was changed.

### Files Added
- `OPTIMIZE.md`

---

## Open Destination Folder on Notification Click (Desktop)

Clicking a "File Received" notification now opens the containing directory in the platform's file manager (`xdg-open` on Linux, `open` on macOS, `explorer.exe` on Windows). The file's parent directory is passed as the notification payload and handled in the click callback.

### Files Modified
- `lib/models/notification_manager.dart` - Added `_openDirectory()`, `_onNotificationResponse()`, payload support in `showNotification()` and `showFileReceivedNotification()`

---

## Vertical-Only Window Resizing on Desktop

Made the main window resizable vertically only (width locked at 540px). Height can now be resized between 600px and 4096px. The initial size remains 540x960.

### Files Modified
- `lib/main.dart` - Added `maxSize` constraint and lowered `minSize` height from 960 to 600

---

## Code Simplification & Deduplication

### Overview
Cleaned up duplicated avatar code, removed dead code, and introduced shared constants for better maintainability.

### Changes Made

#### 1. **Shared Avatar Widget** (NEW: `lib/widgets/peer_avatar.dart`)
- Extracted duplicated avatar building logic from `home.dart` and `peer_details.dart` into a reusable `PeerAvatarWidget`
- Unified color selection, initials extraction, and image/fallback rendering
- Configurable `size`, `borderWidth`, and `refreshStream` parameters

#### 2. **Transfer Constants** (NEW: `lib/config/transfer_constants.dart`)
- Extracted magic bytes (`RDY` signal) and type strings (`AVATAR_FILE`, `FILE`) into named constants
- Used by both `send_service.dart` and `receive_service.dart`

#### 3. **Dead Code Removed**
- `AvatarStore.getDebugInfo()` and `AvatarStore.count` - unused
- `PeerManager.requestAvatarFor()` - unused public method
- `isProcessingComplete` variable in `receive_service.dart` - set but never read
- Redundant `isAvatar` flag in avatar metadata (already has `type: AVATAR_FILE`)

#### 4. **API Simplification**
- `PeerManager.addPeer()` - removed unused `currentIpAddress` and `currentPort` parameters

#### 5. **TOCTOU Fix**
- `_cleanupTempFile()` - removed existence check before delete; catches `FileSystemException` instead

### Files Modified
- `lib/widgets/peer_avatar.dart` - NEW shared avatar widget
- `lib/config/transfer_constants.dart` - NEW transfer protocol constants
- `lib/models/avatars.dart` - removed unused `count` and `getDebugInfo()`
- `lib/models/peer_manager.dart` - removed `requestAvatarFor()`, simplified `addPeer()` signature
- `lib/screens/home.dart` - replaced ~100 lines of avatar code with `PeerAvatarWidget`
- `lib/screens/peer_details.dart` - replaced ~90 lines of avatar code with `PeerAvatarWidget`
- `lib/services/network/receive_service.dart` - use constants, remove dead variable, fix TOCTOU
- `lib/services/network/send_service.dart` - use constants, remove redundant metadata flag
- `lib/services/network/discovery_service.dart` - updated `addPeer()` call

---

## Avatar Handling Improvements

### Overview
Enhanced the avatar handling system to make it more debug-friendly, robust, and easier to maintain while keeping all avatars in memory without local file storage (except temporary files during transfer).

### Changes Made

#### 1. **PeerManager Enhancements** (`lib/models/peer_manager.dart`)
- ✅ **Simplified avatar request flow**: Broke down `addPeer()` into smaller, more readable functions
- ~~`requestAvatarFor()` method~~ (removed in simplification pass - was unused)
- ✅ **Improved error handling**: Better try-catch blocks and logging for avatar requests
- ✅ **Enhanced debugging**: More detailed logging with clear status messages

#### 2. **AvatarStore Improvements** (`lib/models/avatars.dart`)
- ✅ **Better input validation**: Empty peer ID and image data checks
- ✅ **Enhanced error handling**: Detailed error logging with stack traces
- ✅ **Improved memory management**: Safe disposal of existing avatars before replacement
- ~~`getDebugInfo()`, `count` getter~~ (removed in simplification pass - were unused)
- ✅ **Reduced logging verbosity**: Only log when avatars are not found to reduce noise

#### 3. **ReceiveService Enhancements** (`lib/services/network/receive_service.dart`)
- ✅ **Image validation**: Basic image format validation (JPEG, PNG, GIF, WebP)
- ✅ **Robust error handling**: Comprehensive error handling with proper cleanup
- ✅ **Enhanced file cleanup**: Guaranteed temporary file cleanup in `finally` blocks
- ✅ **Better debugging**: Detailed logging throughout the avatar processing pipeline
- ✅ **Input validation**: Empty sender IP checks and file existence validation

#### 4. **SendService Improvements** (`lib/services/network/send_service.dart`)
- ✅ **Improved avatar sending flow**: Separated validation, file checks, and metadata creation
- ✅ **File size validation**: Maximum 10MB limit for avatar files
- ✅ **Better error reporting**: Return boolean success/failure with detailed logging
- ✅ **Enhanced debugging**: Step-by-step logging of avatar send process
- ✅ **Robust validation**: Multiple validation layers before attempting transfer

#### 5. **UI Component Enhancements**

##### Home Screen (`lib/screens/home.dart`)
- ✅ **Improved avatar display**: Better organized `_buildPeerAvatar()` method
- ✅ **Consistent styling**: Border styling for avatar images
- ✅ **Smart fallbacks**: Color-coded default avatars with initials
- ✅ **Reactive updates**: StreamBuilder ensures UI updates when avatars change
- ✅ **Better initials extraction**: Handles single/multiple names properly

##### Peer Details (`lib/screens/peer_details.dart`)
- ✅ **Large avatar support**: Dedicated methods for 80px avatars
- ✅ **Consistent styling**: Matching border and color scheme
- ✅ **Responsive design**: Font sizes scale with avatar size
- ✅ **Enhanced fallbacks**: Improved default avatar appearance

### Technical Benefits

#### 🔧 **Easy to Debug**
- Clear, step-by-step logging throughout the avatar pipeline
- Detailed error messages with stack traces
- Debug utilities for monitoring avatar cache state
- Reduced logging verbosity for common operations

#### 🔧 **Simple to Read**
- Functions broken down into smaller, focused methods
- Clear method names that describe their purpose
- Comprehensive documentation comments
- Consistent error handling patterns

#### 🔧 **Robust Error Handling**
- Input validation at every entry point
- Graceful degradation when avatars fail to load
- Proper cleanup of temporary files in all scenarios
- Network error recovery and retry capabilities

#### 🔧 **Memory Efficient**
- In-memory avatar storage only (no persistent local files)
- Proper disposal of UI Image objects to prevent memory leaks
- Temporary file cleanup guaranteed via `finally` blocks
- Efficient avatar caching with peer ID as key

### Usage Notes

#### Avatar Request Flow
1. **Peer Discovery**: When a new peer is discovered, `PeerManager` automatically requests their avatar
2. **Avatar Transfer**: Uses standard woxxy file transfer functions with special metadata (`type: 'AVATAR_FILE'`)
3. **Memory Storage**: `AvatarStore` loads avatar into memory using `ui.Image`
4. **UI Display**: UI components automatically update when avatars are received
5. **Cleanup**: Temporary files are automatically deleted after processing

#### Error Recovery
- Failed avatar transfers don't block peer discovery
- UI gracefully falls back to initials/default icons
- Network errors are logged but don't crash the app

### Files Modified
- `lib/models/peer_manager.dart` - Enhanced peer and avatar management
- `lib/models/avatars.dart` - Improved avatar storage and debugging
- `lib/services/network/receive_service.dart` - Better avatar reception handling
- `lib/services/network/send_service.dart` - Enhanced avatar sending with validation
- `lib/screens/home.dart` - Improved avatar display in peer list
- `lib/screens/peer_details.dart` - Enhanced large avatar display

### Windows Compatibility Fix

#### 🐛 **Critical Fix: Windows Avatar Transfer Issue**
Fixed a critical issue where avatar transfers would fail on Windows with 0 bytes received despite successful metadata processing.

**Problem**: Windows networking stack would prematurely close sockets during the brief delay between metadata and file data transfer, causing:
- ✅ Metadata received correctly
- ❌ Socket closed with 0 bytes after ~10ms  
- ❌ Avatar files created but empty
- ❌ Avatars not displayed in UI

**Solution**:
1. **Handshake Protocol**: Added ready signal (`RDY`) from receiver to sender
2. **Socket Configuration**: Set `tcpNoDelay` option for better Windows compatibility
3. **Timing Optimization**: Reduced delay from 50ms to 10ms between metadata and data
4. **Enhanced Debugging**: Added Windows-specific error detection and logging
5. **Graceful Fallback**: System continues even if ready signal fails

**Files Modified**:
- `lib/services/network/receive_service.dart` - Added ready signal transmission
- `lib/services/network/send_service.dart` - Added ready signal waiting with timeout

### Backward Compatibility
✅ All changes are backward compatible with existing code. The avatar system continues to:
- Store avatars in memory only
- Use standard woxxy file transfer functions
- Automatically request avatars for new peers
- Display peer avatars in lists and detail screens
- Clean up temporary files properly
- Work seamlessly between Linux, Windows, and other platforms