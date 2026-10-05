# Changes Log

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