import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/models/peer_manager.dart';
import 'package:woxxy/widgets/peer_avatar.dart';

/// 1x1 transparent PNG
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

Peer _peer(String id, {String? hash}) =>
    Peer(name: 'bob', id: id, address: InternetAddress.loopbackIPv4, port: 8090, avatarHash: hash);

void main() {
  group('AvatarStore', () {
    testWidgets('stores an avatar with its hash and notifies only that peer', (tester) async {
      final store = AvatarStore.forTesting();
      var aNotified = 0;
      var bNotified = 0;
      store.listenableFor('a').addListener(() => aNotified++);
      store.listenableFor('b').addListener(() => bNotified++);

      await tester.runAsync(() => store.setAvatar('a', _png, hash: 'h1'));

      expect(store.hasAvatar('a'), isTrue);
      expect(store.avatarHash('a'), 'h1');
      expect(aNotified, 1);
      expect(bNotified, 0);
      store.clear();
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a replaced image stays valid for a grace period and is disposed afterwards', (tester) async {
      final store = AvatarStore.forTesting(disposeDelay: const Duration(milliseconds: 200));
      await tester.runAsync(() => store.setAvatar('a', _png, hash: 'h1'));
      final old = store.getAvatar('a')!;

      await tester.runAsync(() => store.setAvatar('a', _png, hash: 'h2'));
      expect(old.debugDisposed, isFalse, reason: 'a widget may still be painting it this frame');
      expect(store.avatarHash('a'), 'h2');

      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      expect(old.debugDisposed, isTrue);
      store.clear();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('removeAvatar clears the cache entry and notifies listeners', (tester) async {
      final store = AvatarStore.forTesting(disposeDelay: Duration.zero);
      await tester.runAsync(() => store.setAvatar('a', _png));
      final notifier = store.listenableFor('a');
      expect(notifier.value, isNotNull);

      store.removeAvatar('a');
      expect(store.hasAvatar('a'), isFalse);
      expect(notifier.value, isNull);
      await tester.pump(const Duration(milliseconds: 10)); // flush the deferred dispose timer
    });
  });

  group('PeerManager avatar sync', () {
    late DateTime now;
    late AvatarStore store;
    late PeerManager manager;
    late List<String> requests;

    setUp(() {
      now = DateTime(2026, 1, 1, 12);
      store = AvatarStore.forTesting(disposeDelay: Duration.zero);
      manager = PeerManager(avatarStore: store, clock: () => now);
      requests = [];
      manager.setRequestAvatarCallback((p) => requests.add('${p.id}:${p.avatarHash}'));
    });

    tearDown(() => manager.dispose());

    test('a peer announcing an avatar hash is asked for it, a peer without avatar is not', () {
      manager.addPeer(_peer('with', hash: 'h1'));
      manager.addPeer(_peer('without'));
      expect(requests, ['with:h1']);
    });

    test('requests are throttled while the avatar is still missing, then retried', () {
      manager.addPeer(_peer('p', hash: 'h1'));
      now = now.add(const Duration(seconds: 5));
      manager.addPeer(_peer('p', hash: 'h1'));
      expect(requests, hasLength(1));

      now = now.add(const Duration(seconds: 30));
      manager.addPeer(_peer('p', hash: 'h1'));
      expect(requests, hasLength(2));
    });

    testWidgets('a cached avatar with the announced hash is not requested again, a changed hash is', (tester) async {
      await tester.runAsync(() => store.setAvatar('p', _png, hash: 'h1'));

      manager.addPeer(_peer('p', hash: 'h1'));
      expect(requests, isEmpty);

      manager.addPeer(_peer('p', hash: 'h2'));
      expect(requests, ['p:h2']);
    });

    testWidgets('an avatar is evicted when the peer stops announcing one or leaves', (tester) async {
      await tester.runAsync(() async {
        await store.setAvatar('p', _png, hash: 'h1');
        await store.setAvatar('q', _png, hash: 'h1');
      });
      manager.addPeer(_peer('p', hash: 'h1'));
      manager.addPeer(_peer('q', hash: 'h1'));

      manager.addPeer(_peer('p')); // p removed its avatar
      expect(store.hasAvatar('p'), isFalse);

      now = now.add(const Duration(minutes: 1));
      manager.removeStalePeers(); // q left
      expect(store.hasAvatar('q'), isFalse);
      await tester.pump(const Duration(milliseconds: 10)); // flush deferred dispose timers
    });
  });

  group('PeerAvatarWidget', () {
    testWidgets('an update for one peer only changes that peer avatar', (tester) async {
      final store = AvatarStore();
      final a = _peer('widget-a-${DateTime.now().microsecondsSinceEpoch}');
      final b = _peer('widget-b-${DateTime.now().microsecondsSinceEpoch}');

      await tester.pumpWidget(MaterialApp(
        home: Row(children: [PeerAvatarWidget(peer: a), PeerAvatarWidget(peer: b)]),
      ));
      expect(find.byType(RawImage), findsNothing);

      await tester.runAsync(() => store.setAvatar(a.id, _png));
      await tester.pump();

      expect(find.byType(RawImage), findsOneWidget);
      expect(find.text('B'), findsOneWidget); // b still shows its initials
      store.removeAvatar(a.id);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
