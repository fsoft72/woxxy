# Optimization TODO

> Generated on 2026-10-05. Items sorted by importance.

## Not issues (by design)

These two items were in the first analysis as "Critical" and were reviewed by the maintainer: they are not problems. Woxxy is a trusted-LAN tool where receiving files automatically is the intended behavior, so no consent step or peer allow-list is needed.

- **Receiver accepts files without consent** - intended: transfers are received automatically, the size cap and filename sanitizing are the accepted protection.
- **Avatar owner taken from metadata `senderIp`** - accepted: the peer id is the IP and the LAN is trusted, so the metadata value is not treated as a security boundary.

## High

- [x] **No connection limit and no idle timeout on the server** - A sender that connects and stalls keeps a socket, an open `IOSink` and a `FileTransferManager.files` entry forever, and the number of parallel connections is unbounded. Add a max concurrent connections value and a read inactivity timeout that triggers `handleSocketClosure`.
  - File(s): `lib/services/network/server_service.dart`, `lib/services/network/receive_service.dart`
- [x] **Write failures are ignored while receiving** - `FileTransferManager.write` swallows errors and returns `false`, but `handleNewConnection` never checks the result, so a full disk or a revoked folder keeps the transfer "running" until the MD5 check fails at the end. Check the return value and abort the transfer right away.
  - File(s): `lib/services/network/receive_service.dart` (lines 58 and 75), `lib/models/file_transfer_manager.dart`
- [x] **No real backpressure on disk writes** - `FileTransfer.write` calls `fileSink.add` without awaiting anything, so if the disk is slower than the network the data piles up in memory. The doc comment of `handleNewConnection` promises backpressure that does not exist. Await `fileSink.flush()` every N bytes (or pipe through `addStream`).
  - File(s): `lib/models/file_transfer.dart`, `lib/services/network/receive_service.dart`
- [x] **Avatar requests have no rate limit** - Every UDP `avatar_request` makes the device hash/read the avatar and open a TCP connection. A single host can flood this path. Limit requests per source IP (for example one per few seconds) and ignore the rest.
  - File(s): `lib/services/network/discovery_service.dart`, `lib/services/network/send_service.dart`
- [x] **Local identity is copied into three services** - Username, IP and profile image are stored in `NetworkService`, `SendService` and `DiscoveryService`, and the same fan-out of `updateUserDetails` calls is repeated in `start`, `setUsername`, `setProfileImagePath` and `_handleIpChanged`. Introduce one `LocalIdentity` value object (or `ValueNotifier`) that the services read, so there is a single source of truth.
  - File(s): `lib/services/network_service.dart`, `lib/services/network/send_service.dart`, `lib/services/network/discovery_service.dart`
- [x] **Received-file side effects live inside a widget** - `HomePage` listens to `onFileReceived` to write the history and show the notification, and drops the event when `!mounted`. A file received while the window is closed or the tree is rebuilt is missing from the history. Move this wiring to a plain class created in `AppServices` and keep `HomePage` for UI only.
  - File(s): `lib/screens/home_page.dart`, `lib/app_services.dart`
- [x] **`HomePage` disposes a service it does not own** - `AppServices` creates `NetworkService` in `main()`, but `_HomePageState.dispose` calls `_networkService.dispose()`. After that the service cannot be started again and any other holder breaks. Let the owner of `AppServices` dispose it.
  - File(s): `lib/screens/home_page.dart`, `lib/main.dart`

## Medium

- [x] **Whole file is hashed before the first byte is sent** - `_createFileMetadata` reads the file once for MD5 and then again to send, so big files wait a long time with no progress. Show a "preparing" state in `SendQueueController` or compute the checksum while streaming and send it in a trailer.
  - File(s): `lib/services/network/send_service.dart`, `lib/services/send_queue_controller.dart`
- [x] **Hashing code is duplicated and verbose** - `_createFileMetadata` builds a `Completer` around `openRead().transform(md5).listen`, while `NetworkService._avatarHashFor` does the same with `md5.bind(...).first` in one line. Extract one `md5OfFile(File)` helper in `lib/funcs/` and use it in both places. Also replace the `"CHECKSUM_ERROR"` magic string with a nullable checksum.
  - File(s): `lib/services/network/send_service.dart`, `lib/services/network_service.dart`, `lib/models/file_transfer.dart`
- [x] **Timing-based heuristic for premature closure** - `_onConnectionClosed` treats "0 bytes in less than 100 ms" as a special Windows case, but the next branch (`receivedBytes < dataExpected`) already handles it identically. Remove the branch and the magic `100`.
  - File(s): `lib/services/network/receive_service.dart`
- [x] **In-flight receives are not stopped on dispose** - `ServerService.dispose` only closes the listening socket and `ReceiveService.dispose` is a no-op, so active incoming sockets and file sinks stay open. Track active sockets in `ReceiveService` and destroy them on dispose.
  - File(s): `lib/services/network/server_service.dart`, `lib/services/network/receive_service.dart`
- [x] **Received avatar is decoded without dimension limits** - Only the byte size is limited (10 MB), but a small compressed image can decode to a huge bitmap. Pass `targetWidth`/`targetHeight` to `ui.instantiateImageCodec` (avatars are shown at most 80 px).
  - File(s): `lib/models/avatars.dart`
- [x] **History is saved without ordering or error handling** - `autoSave` fires an un-awaited `save` on every change; two quick changes can finish out of order and a failure is an unhandled async error. Serialize the writes (single in-flight future plus "dirty" flag) and catch errors.
  - File(s): `lib/services/history_repository.dart`
- [x] **`PeerManager` is created inside `NetworkService` and wired by setter** - The constructor builds `PeerManager` itself and `setRequestAvatarCallback` closes the circular dependency afterwards, which makes the order of construction important and hard to test. Inject `PeerManager` (like the other collaborators) and pass the avatar request function at construction. Also align `SendAvatarCallback` (`Future<void>`) with `SendService.sendAvatar` (`Future<bool>`).
  - File(s): `lib/services/network_service.dart`, `lib/models/peer_manager.dart`, `lib/services/network/discovery_service.dart`
- [x] **Settings screen updates state after an `await` without `mounted`** - `_pickDirectory` calls `setState` after `updateDownloadPath` without checking `mounted`, and ignores the `false` result (invalid folder is still saved in the user). Check both.
  - File(s): `lib/screens/settings.dart`
- [x] **Settings are saved fire-and-forget** - `_updateUser` in `HomePage` calls `saveSettings` without `await` and without error handling, and `SettingsService.saveSettings` writes three keys one after another. Await the call, report failures and write only what changed.
  - File(s): `lib/screens/home_page.dart`, `lib/services/settings_service.dart`

## Low / Nice to have

- [x] **Default username defined in six places with two different values** - `'WoxxyUser'` is repeated in `NetworkService`, `SendService` and `DiscoveryService`, while `SettingsService` defaults to `'User'`. Create `DEFAULT_USERNAME` in `lib/config/` and use it everywhere.
  - File(s): `lib/services/network_service.dart`, `lib/services/network/send_service.dart`, `lib/services/network/discovery_service.dart`, `lib/services/settings_service.dart`
- [x] **`utils.dart` mixes unrelated responsibilities** - UI (`showSnackbar`), process launching (`openFileLocation`), id generation and formatting live in one file, and the "open folder" platform switch is repeated in `NotificationManager._openDirectory`. Split into `ui_helpers`, `file_opener` (shared by both callers) and `format`.
  - File(s): `lib/funcs/utils.dart`, `lib/models/notification_manager.dart`
- [ ] **Size formatting is inconsistent** - `formatBytes` exists, but `HistoryScreen` and `SendQueueController._onSuccess` do their own `/ 1024 / 1024` and `toStringAsFixed`, and `send_service.dart` uses a raw `1024`. Reuse `formatBytes` and `BYTES_PER_MB`.
  - File(s): `lib/screens/history.dart`, `lib/services/send_queue_controller.dart`, `lib/services/network/send_service.dart`
- [ ] **`FileTransfer.start` has eight positional parameters** - `key` and `sourceIp` overlap and the order is easy to get wrong. Switch to named parameters and drop the redundant `key`.
  - File(s): `lib/models/file_transfer.dart`, `lib/models/file_transfer_manager.dart`
- [ ] **Outdated and noisy comments** - Leftovers such as "Removed userId", "Removed _loadSettings method", "FIX: Add '!'", "// End of FileTransferManager class" and the "Consider how to handle..." notes describe history, not the code. Delete them or turn them into real decisions.
  - File(s): `lib/services/settings_service.dart`, `lib/screens/home_page.dart`, `lib/models/file_transfer.dart`, `lib/models/file_transfer_manager.dart`
- [ ] **Dead defensive code in `HomePage`** - `_currentUser` is always set from `initialUser`, so the null branches in `_getScreens` and `build` can never run, and `_getScreens()` rebuilds the screen list on every build. Make `_currentUser` non-nullable and build the list once.
  - File(s): `lib/screens/home_page.dart`
- [ ] **Logging in the build path of the peer list** - `StreamBuilder` calls `zprint` twice per rebuild; in release builds the strings are still built. Use `zprintLazy` or remove them.
  - File(s): `lib/screens/home.dart`
- [ ] **Avatar color depends on `String.hashCode`** - The same peer can get a different color on different platforms because the hash is not guaranteed to be stable. Use a simple deterministic hash (for example sum of code units).
  - File(s): `lib/widgets/peer_avatar.dart`
- [ ] **`AvatarStore` never releases notifiers and has an unused debug getter** - `_notifiers` grows with every peer id ever seen and `getKeys()` is not used. Dispose the notifier in `removeAvatar` when it has no listeners and remove `getKeys`.
  - File(s): `lib/models/avatars.dart`
- [ ] **Version is defined twice and `env.dart` is a dangling symlink** - `APP_VERSION` in `version.dart` must be kept in sync with `pubspec.yaml` by hand, and `lib/config/env.dart` is tracked in git as a symlink to a file that does not exist (`git ls-files | xargs wc` fails on it). Generate the version from `pubspec.yaml` (or read it with `package_info_plus`) and remove or fix the symlink.
  - File(s): `lib/config/version.dart`, `lib/config/env.dart`, `pubspec.yaml`
