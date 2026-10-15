# Optimization TODO

> Generated on 2026-10-15. Items sorted by importance.

## Critical

Nothing critical found: the analyzer is clean, transfers are size-limited, sanitized, verified and cancellable.

## High

- [ ] **Leaving the peer page silently cancels the transfers** - `SendQueueController` is created and disposed by `_PeerDetailPageState`, so pressing Back while a big file (or a queue) is being sent cancels it without any warning; move the queues into an app-level owner (for example a `SendQueues` registry keyed by peer id in `AppServices`) so the page only observes them, or at least confirm before popping while `hasWork` is true.
  - File(s): `lib/screens/peer_details.dart`, `lib/services/send_queue_controller.dart`, `lib/app_services.dart`

- [x] **Every sent file is read from disk twice** - `SendService._createFileMetadata` hashes the whole file with `md5OfFile` before the first byte is sent, so a multi-GB file spends as long in "Preparing..." as in the transfer itself; compute the MD5 while streaming (as the receiver already does in `FileTransfer.write`) and send it in a short trailer after the data, keeping the header checksum for older receivers behind a protocol version field.
  - File(s): `lib/services/network/send_service.dart`, `lib/services/network/receive_service.dart`, `lib/services/network/transfer_protocol.dart`

- [x] **Received avatars are stored under an IP taken from the metadata** - `_onConnectionClosed` passes `info['senderIp']` to `_processReceivedAvatar`, so any host on the LAN can replace the avatar of another peer by writing that peer's address in the JSON; use the socket `sourceIp` (already known in `handleNewConnection`) and drop `senderIp` from the avatar metadata.
  - File(s): `lib/services/network/receive_service.dart`, `lib/services/network/send_service.dart`

- [x] **Transfer metadata is an untyped map with string keys spread over four files** - `'name'`, `'size'`, `'type'`, `'md5Checksum'`, `'senderUsername'`, `'senderIp'` and `'transferId'` are written in `SendService` and read with ad hoc casts and fallbacks in `ReceiveService._acceptTransfer`, `_onConnectionClosed` and `FileTransferManager.add`; introduce a `TransferMetadata` class with `toJson`/`fromJson` (validation in one place) and pass it instead of `Map<String, dynamic>`.
  - File(s): `lib/services/network/send_service.dart`, `lib/services/network/receive_service.dart`, `lib/models/file_transfer_manager.dart`, `lib/models/file_transfer.dart`

- [ ] **The IP shown in the app bar never updates** - `HomePage.build` reads `_networkService.currentIpAddress` once per rebuild, but nothing rebuilds the page when `IpMonitor` reports a new address, so after a Wi-Fi switch the header shows the old IP; expose the address as a `ValueListenable<String?>` (or a stream) from `NetworkService` and wrap the header text in a `ValueListenableBuilder`.
  - File(s): `lib/screens/home_page.dart`, `lib/services/network_service.dart`, `lib/models/local_identity.dart`

## Medium

- [x] **Send speed includes the hashing time** - the stopwatch in `SendQueueController._processQueue` starts before `_send`, which first hashes the file, so both the live MB/s and the final "File sent successfully" speed are underestimated for large files; start timing on the first progress callback (when `_preparing` turns false).
  - File(s): `lib/services/send_queue_controller.dart`

- [x] **Send queue state is spread over five booleans** - `_processing`, `_isTransferring`, `_preparing`, `_transferComplete` and `_disposed` are set in several places (`addFiles`, `_processQueue`, `cancelAll`, `_onSuccess`) and only some combinations are valid; replace the first four with one `SendPhase` enum (`idle`, `preparing`, `sending`, `completed`) so the UI reads a single value.
  - File(s): `lib/services/send_queue_controller.dart`, `lib/screens/peer_details.dart`

- [x] **`sendFile` and `sendAvatar` duplicate the transfer lifecycle** - both add the id to `_liveTransfers`, validate the local IP, build metadata and remove the id in `finally`, and the class keeps two parallel collections (`_liveTransfers` and `_activeTransfers`) for one concept; extract a private `_runTransfer(id, body)` helper and merge the collections into one `Map<String, Socket?>`.
  - File(s): `lib/services/network/send_service.dart`

- [x] **Avatars take a round trip through the disk** - incoming avatars (at most 10 MB) are written to a temp folder by `FileTransferManager`, read back with `readAsBytes`, hashed again with `md5.convert` and deleted; collect them in memory in `ReceiveService` and reuse the checksum already verified by `FileTransfer`.
  - File(s): `lib/services/network/receive_service.dart`, `lib/models/file_transfer_manager.dart`

- [x] **`FileTransferManager.files` is a public mutable map** - `ReceiveService` reads it directly and tests clear it, so any caller can bypass `add`/`end`/`handleSocketClosure`; make it private, expose `FileTransfer? operator [](String key)` and a `@visibleForTesting reset()`, and make `downloadPath` settable only through `updateDownloadPath`.
  - File(s): `lib/models/file_transfer_manager.dart`, `lib/services/network/receive_service.dart`, `test/file_transfer_manager_test.dart`, `test/transfer_loopback_test.dart`

- [x] **Leftover fields and fallbacks in `FileTransfer` and `FileTransferManager.add`** - `FileTransfer.metadata` is stored but never read, `sourceIp` is documented as "the key in FileTransferManager" (the key is now `ip#transferId`), `add` falls back to `sourceIp ?? key` and takes an `md5Checksum` parameter that is immediately overridden by `metadata['md5Checksum']`; remove the dead field and the redundant parameter and fix the doc.
  - File(s): `lib/models/file_transfer.dart`, `lib/models/file_transfer_manager.dart`

- [x] **Redundant lookups and duplicate cleanup in `FileTransferManager`** - every method does `containsKey(key)` then `files[key]!`, and the `catch` of `end()` deletes the file again although `FileTransfer.end()` already deletes it on failure; use a single `final transfer = files.remove(key)` at the top of `end`/`handleSocketClosure` with an early `if (transfer == null) return false;`.
  - File(s): `lib/models/file_transfer_manager.dart`

## Low / Nice to have

- [x] **Hand-written image sniffing duplicates the real decoder check** - `ReceiveService._isValidImageData` checks magic bytes (and accepts GIF and WebP, which the settings picker never offers) right before `AvatarStore.setAvatar` decodes the image and throws on invalid data anyway; remove the sniffer and rely on the decoder.
  - File(s): `lib/services/network/receive_service.dart`

- [ ] **`Peer` has no equality and carries unused JSON code** - `PeerManager.addPeer` compares name, port, address and avatarHash field by field, while `Peer.toJson`/`Peer.fromJson` are never used; add `==`/`hashCode` to `Peer`, use them in `addPeer`, and drop the dead serialization.
  - File(s): `lib/models/peer.dart`, `lib/models/peer_manager.dart`

- [x] **Metadata decoder copies its buffer on every chunk** - `MetadataFrameDecoder.add` calls `_buffer.toBytes()` for each incoming chunk until the header is complete, which is quadratic for headers near the 1 MB limit; read the 4-byte length once and copy only when `_length >= frameEnd`.
  - File(s): `lib/services/network/transfer_protocol.dart`

- [ ] **Small cleanups in `HomePage`** - `_initializeApp` only calls `_startNetwork`, `dispose` is an empty override, the `mounted` check in `onDestinationSelected` is unnecessary, and the IP condition is evaluated twice in `build`; remove the wrappers and keep one local `ip` variable.
  - File(s): `lib/screens/home_page.dart`

- [ ] **Debug test-notification button inside the production widget** - `HomeContent` hard-codes `/tmp/test.txt` and fake values behind `kDebugMode`; move it to a debug-only menu or delete it so `HomeContent` has a single responsibility (the peer list).
  - File(s): `lib/screens/home.dart`

- [x] **Magic values in discovery and the send handshake** - `'NO_IP'` in `_buildDiscoveryMessage`, the inline `Duration(seconds: 3)` default of `restartDelay`, and the index-by-index `READY_SIGNAL` comparison in `_waitForReadySignal`; add `DISCOVERY_RESTART_DELAY` to `network_constants.dart`, skip the announcement when the IP is null, and compare with `listEquals`.
  - File(s): `lib/services/network/discovery_service.dart`, `lib/services/network/send_service.dart`, `lib/config/network_constants.dart`

- [ ] **Linux notification icon looked up on every notification** - `LinuxNotificationBackend.show` calls `_iconPath()`, which runs a synchronous `existsSync` each time; resolve it once in `init` and keep it in a field.
  - File(s): `lib/models/notifications/linux_notification_backend.dart`

- [x] **`sendFile` returns the id it was given** - `SendService.sendFile`, `NetworkService.sendFile` and the `SendFileFunction` typedef return `Future<String>` holding the caller's own `transferId`; return `Future<void>` to make the contract honest.
  - File(s): `lib/services/network/send_service.dart`, `lib/services/network_service.dart`, `lib/services/send_queue_controller.dart`

- [ ] **Duplicated doc comment and missing class docs** - `FileHistoryEntry.speedMBps` has the same doc line twice, and public classes such as `Peer`, `User`, `SettingsService`, `ServerService`, `DiscoveryService`, `ReceiveService` and `SendService` have no class-level doc comment.
  - File(s): `lib/models/history.dart`, `lib/models/peer.dart`, `lib/models/user.dart`, `lib/services/settings_service.dart`, `lib/services/network/*.dart`
