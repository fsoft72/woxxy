# Optimization TODO

> Generated on 2026-10-05. Items sorted by importance.

## Critical

- [x] **Sanitize the remote filename (path traversal)** - The receiver builds the destination with `path.join(downloadPath, metadata['name'])` using an unvalidated name from the network, so a name like `../../.bashrc` writes outside the download folder. Apply `path.basename` plus a reject list (empty, `.`, `..`, separators) before generating the unique path.
  - File(s): `lib/models/file_transfer.dart`, `lib/services/network/receive_service.dart`
- [ ] **Stop keying transfers by source IP only** - `FileTransferManager.files` is keyed by the sender IP, so an avatar transfer (sent automatically on peer discovery) or a second file from the same peer overwrites and corrupts the active transfer; the avatar is also written into the user's download folder. Key by `transferId` (already in the metadata) and write avatars to a temp directory. The `exists()` check in `_generateUniqueFilePath` followed by `openWrite` is also a race for same-name files.
  - File(s): `lib/models/file_transfer_manager.dart`, `lib/models/file_transfer.dart`, `lib/services/network/receive_service.dart`
- [ ] **Serialize the receive handler (race on metadata and data)** - `socket.listen((data) async {...})` does not wait for the previous callback, so chunks arriving during `await fileTransferManager.add(...)` or `socket.flush()` are appended to `buffer` and the metadata is parsed and added a second time, or file data is written out of order. Pause the subscription while handling metadata, or use a small state machine over a `StreamIterator`/`StreamTransformer` that frames the stream sequentially.
  - File(s): `lib/services/network/receive_service.dart`
- [ ] **Do not buffer the whole received file in RAM for MD5** - `FileTransfer._receivedData` keeps every byte in a `List<int>` just to compute the checksum at the end, so a multi-GB transfer exhausts memory (and `addAll` on boxed ints makes it worse). Use `md5.startChunkedConversion` with an `AccumulatorSink<Digest>` and feed each chunk as it is written.
  - File(s): `lib/models/file_transfer.dart`

## High

- [ ] **Respect backpressure when sending** - `SendService._sendFileWithMetadata` calls `socket.add(chunk)` in a `listen` callback without pausing, so a fast disk and a slow network queue the whole file in the socket buffer. Replace the manual subscription with `socket.addStream(file.openRead().map(...))` (count bytes in `map`) and then `flush()`.
  - File(s): `lib/services/network/send_service.dart`
- [ ] **Throttle progress updates to the UI** - `onProgress` runs once per 64 KB chunk and each call does `setState` in `PeerDetailPage`, which rebuilds the whole page thousands of times per second. Emit progress at most every ~100 ms or on a 1% change, or expose it through a `ValueNotifier` consumed only by the progress widget.
  - File(s): `lib/screens/peer_details.dart`, `lib/services/network/send_service.dart`
- [ ] **Fix notification click on Linux and the fixed notification id** - `_linuxInitialize` registers an inline callback that only logs, so `_onNotificationResponse` (and the "open folder" feature) never runs on Linux; the `_lastNotificationDirPath` workaround is therefore dead. Also every notification uses id `0`, so a new one replaces the previous one. Pass `_onNotificationResponse` and use an incrementing id.
  - File(s): `lib/models/notification_manager.dart`
- [ ] **Remove UI side effects from the `FileTransfer` model** - `FileTransfer.end()` calls `NotificationManager.instance` directly and `FileTransferManager` adds history entries, so the data layer depends on the UI layer and cannot be tested in isolation. Have `end()` only return the result and let one coordinator (the manager emitting an event) trigger history and notification.
  - File(s): `lib/models/file_transfer.dart`, `lib/models/file_transfer_manager.dart`
- [ ] **Replace the stringly-typed `onFileReceived` stream** - `NetworkService` emits `"Received: name from sender"` but `_HomePageState._setupFileReceivedListener` splits on `|` and expects 4+ parts, so that listener always logs "invalid file info format" and is dead code. Emit a typed `FileReceivedEvent` (path, size, speed, sender) and keep a single consumer; store and cancel the `StreamSubscription` (it is never cancelled in `HomePage`, and `HomeContent.initState` subscribes again without cancelling).
  - File(s): `lib/services/network_service.dart`, `lib/main.dart`, `lib/screens/home.dart`
- [ ] **Handle network start failure** - `NetworkService.start()` returns silently when no IP is found and rethrows otherwise, but `_initializeApp()` is called un-awaited from `initState`, so the user sees an endless spinner (`_isLoading` never becomes false) with no message. Surface a state (`starting`, `ready`, `error`) and show an error screen with a retry button.
  - File(s): `lib/main.dart`, `lib/services/network_service.dart`
- [ ] **Make the discovery protocol robust** - Announcements use a `:`-delimited string, so a username containing `:` breaks parsing, and the receive side uses `String.fromCharCodes` while the sender uses `utf8.encode`, which garbles non-ASCII names (accents, emoji). Send a small JSON payload and decode with `utf8.decode`; include a protocol version.
  - File(s): `lib/services/network/discovery_service.dart`
- [ ] **Add automated tests** - There is no `test/` directory, so the transfer protocol, checksum logic and peer lifecycle have no safety net. Start with unit tests for metadata framing, filename sanitization, `FileHistory`, `PeerManager` timeouts and the MD5 check, then a loopback send/receive integration test.
  - File(s): `test/` (new), `lib/services/network/*.dart`, `lib/models/*.dart`

## Medium

- [ ] **Harden the receiver against hostile peers** - Any LAN host can push a file with no confirmation, `receivedBytes` is never compared to `dataExpected` while streaming (a sender can send unlimited data), and the declared size is not checked against free disk space. Reject data beyond the declared size, cap the size, and optionally ask the user to accept from unknown peers.
  - File(s): `lib/services/network/receive_service.dart`
- [ ] **Fix `PeerManager` lifecycle and updates** - It is a singleton whose `BehaviorSubject` is closed by `NetworkService.dispose()` (later `add` throws), `_requestAvatarCallback` is `late` and throws if `addPeer` runs before wiring, an existing peer only refreshes `lastSeen` so renamed users or changed ports are never updated, and the cleanup timer period equals the timeout so a dead peer can stay up to ~60 s.
  - File(s): `lib/models/peer_manager.dart`, `lib/services/network_service.dart`
- [ ] **Fix avatar cache correctness and rebuild cost** - Avatars are never refreshed (`hasAvatar` short-circuits the request) or evicted when a peer leaves; `AvatarStore.setAvatar` disposes the old `ui.Image` while a `RawImage` may still paint it (disposed-image crash); each `PeerAvatarWidget` subscribes to the full peer stream so every peer update rebuilds all avatars; and `getAvatar` logs on every miss inside `build`. Add a version/hash to the announcement, dispose on eviction after the frame, and notify per peer id.
  - File(s): `lib/models/avatars.dart`, `lib/widgets/peer_avatar.dart`, `lib/models/peer_manager.dart`
- [ ] **Recover from discovery socket loss and IP changes** - When the UDP socket closes or errors, the timer is cancelled and nothing restarts it; the local IP is read once at startup, so switching Wi-Fi leaves the app announcing a stale address; broadcast goes only to `255.255.255.255`. Re-detect the IP periodically and rebind/restart discovery, and use per-interface broadcast addresses.
  - File(s): `lib/services/network/discovery_service.dart`, `lib/services/network_service.dart`
- [ ] **Keep tab state with `IndexedStack`** - `_getScreens()` builds new screen widgets on every `build` and only `screens[_selectedIndex]` is mounted, so switching tabs destroys `HomeContent`/`SettingsScreen` state and re-runs `initState`. Build the screens once and show them with `IndexedStack`.
  - File(s): `lib/main.dart`
- [ ] **Fix `FileHistory` sorting, persistence and notifications** - The `entries` getter sorts the underlying list on every access and is called inside `itemBuilder` for each row (O(n log n) per item); history is lost on restart although `toJson`/`fromJson` exist; the UI needs manual `setState` instead of a `ChangeNotifier`. Insert at index 0 (or sort once), make it a `ChangeNotifier`, persist it, and use `ListenableBuilder` in `HistoryScreen`.
  - File(s): `lib/models/history.dart`, `lib/screens/history.dart`, `lib/main.dart`
- [ ] **Fix the settings screen behaviors** - `_updateUser` runs on every keystroke, writing to `SharedPreferences` and changing the announced username for each character (debounce or save on submit, reject empty names); SVG avatars are offered but rendered with `SvgPicture.asset` on a file path (should be `SvgPicture.file`) and the receiver rejects SVG data, so either drop `svg` from `allowedExtensions` or support it end to end; the picked image path is referenced in place and breaks if the file moves (copy it into app support).
  - File(s): `lib/screens/settings.dart`, `lib/services/network/receive_service.dart`
- [ ] **Split `main()` and fix the fatal error screen** - `main()` is ~190 lines mixing settings, download dir, window, icon, tray and notifications, and its error handler checks `isRootWidgetAttached`, which is always false before the first `runApp`, so the "Failed to initialize" screen never shows. Extract `DesktopShell` (window and tray) and `_resolveDownloadPath()`, move `HomePage` to `lib/screens/`, and call `runApp` unconditionally in the catch block.
  - File(s): `lib/main.dart`
- [ ] **Break up `peer_details.dart`** - The 635-line page holds queue logic, transfer state and four builders; `_progressSubscription` is never assigned, `newFiles` is unused, and `_formatFileSize` duplicates other size formatting. Move queue/transfer state to a `SendQueueController` (`ChangeNotifier`) and extract `TransferProgressCard`, `QueueSummary` and `DropZone` widgets; share one `formatBytes` helper.
  - File(s): `lib/screens/peer_details.dart`, `lib/funcs/utils.dart`
- [ ] **Refactor `NotificationManager` per platform** - One class holds Android, Windows, macOS and Linux init and show logic in long `if (Platform.isX)` chains, with stray `print("DEBUG LINUX...")`, `\n\n\n=== NOTIF` logging and a commented-out block. Introduce a small `NotificationBackend` interface with one implementation per platform, and route all logging through `zprint`.
  - File(s): `lib/models/notification_manager.dart`
- [ ] **Inject dependencies instead of singletons** - `FileTransferManager`, `PeerManager`, `AvatarStore`, `NotificationManager` are global singletons, `NetworkService` reads `FileTransferManager.instance` in a field initializer (crashes if created first) and `SettingsService()` is instantiated in three places. Pass instances through constructors from `main()` so services can be faked in tests.
  - File(s): `lib/services/network_service.dart`, `lib/models/file_transfer_manager.dart`, `lib/models/peer_manager.dart`, `lib/models/avatars.dart`, `lib/main.dart`

## Low / Nice to have

- [ ] **Centralize constants and style cleanups** - Magic strings and numbers are scattered: `'AVATAR_FILE'` and `'FILE'` literals instead of `TRANSFER_TYPE_*`, ports `8090/8091`, timeouts (5 s ready signal, 10 s connect, 30 s peer), the 10 MB avatar limit and the 1 MB metadata limit. `FileTransfer` also uses snake_case fields under `ignore_for_file`, `withOpacity` is deprecated (use `withValues(alpha:)`), and `generateTransferId` (md5 of name and millisecond) can collide; use a counter or UUID.
  - File(s): `lib/config/transfer_constants.dart`, `lib/models/file_transfer.dart`, `lib/models/file_transfer_manager.dart`, `lib/services/network_service.dart`, `lib/services/network/send_service.dart`, `lib/services/network/receive_service.dart`, `lib/funcs/utils.dart`, `lib/screens/peer_details.dart`
- [ ] **Make logging cheap in release builds** - `zprint` returns early in product mode, but callers still build the interpolated string (for example `json.encode(metadata)` and full metadata maps) before the call, and several files use `print` directly. Make `zprint` take a `String Function()` or guard heavy calls with `kDebugMode`, and replace direct `print`.
  - File(s): `lib/funcs/debug.dart`, `lib/services/network/send_service.dart`, `lib/models/file_transfer.dart`, `lib/models/notification_manager.dart`
