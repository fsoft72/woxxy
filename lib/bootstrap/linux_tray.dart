// ignore_for_file: constant_identifier_names

import 'dart:io';
import 'dart:ui' as ui;

import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';
import 'package:woxxy/funcs/debug.dart';

/// One entry of the Linux tray menu. A null [label] makes the entry a separator.
class LinuxTrayItem {
  final String? label;
  final Future<void> Function()? onClick;

  const LinuxTrayItem({this.label, this.onClick});

  /// A separator line.
  const LinuxTrayItem.separator() : this();

  /// True for separator entries.
  bool get isSeparator => label == null;
}

/// System tray icon for Linux, speaking StatusNotifierItem and dbusmenu over D-Bus directly.
///
/// The tray_manager plugin goes through libappindicator, which only sends the icon as a file path.
/// Some tray hosts cannot load such an icon and show it broken, so here the icon is sent as raw
/// pixels (`IconPixmap`), which every host understands.
class LinuxTray {
  static const String _ITEM_INTERFACE = 'org.kde.StatusNotifierItem';
  static const String _WATCHER_NAME = 'org.kde.StatusNotifierWatcher';
  static const String _WATCHER_INTERFACE = 'org.kde.StatusNotifierWatcher';
  static const String _MENU_INTERFACE = 'com.canonical.dbusmenu';
  static const List<int> _ICON_SIZES = [22, 32, 64];

  final String title;
  final String iconAsset;
  final List<LinuxTrayItem> items;
  final Future<void> Function() onActivate;

  final DBusClient _client = DBusClient.session();
  _StatusNotifierItem? _item;
  _DBusMenu? _menu;

  /// [iconAsset] is a Flutter asset path, [onActivate] runs on a left click on the icon.
  LinuxTray({required this.title, required this.iconAsset, required this.items, required this.onActivate});

  /// Publishes the icon and the menu on the session bus and registers them with the tray host.
  Future<void> start() async {
    final pixmaps = await _loadPixmaps();
    final busName = 'org.kde.StatusNotifierItem-$pid-1';

    _menu = _DBusMenu(items);
    _item = _StatusNotifierItem(title: title, pixmaps: pixmaps, onActivate: onActivate);
    await _client.requestName(busName);
    await _client.registerObject(_menu!);
    await _client.registerObject(_item!);

    await _client.callMethod(
      destination: _WATCHER_NAME,
      path: DBusObjectPath('/StatusNotifierWatcher'),
      interface: _WATCHER_INTERFACE,
      name: 'RegisterStatusNotifierItem',
      values: [DBusString(busName)],
      replySignature: DBusSignature(''),
    );
  }

  /// Removes the icon from the tray.
  Future<void> stop() async {
    await _client.close();
    _item = null;
    _menu = null;
  }

  /// Decodes the icon asset at every size in [_ICON_SIZES] as ARGB32 pixmaps.
  Future<List<_Pixmap>> _loadPixmaps() async {
    final data = await rootBundle.load(iconAsset);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final pixmaps = <_Pixmap>[];

    for (final size in _ICON_SIZES) {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: size, targetHeight: size);
      final frame = await codec.getNextFrame();
      final rgba = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) throw StateError('Cannot decode the tray icon $iconAsset at ${size}px');

      pixmaps.add(_Pixmap(size, size, _rgbaToArgb(rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes))));
      frame.image.dispose();
      codec.dispose();
    }
    return pixmaps;
  }

  /// StatusNotifierItem wants the bytes of each pixel as A, R, G, B, while Flutter gives R, G, B, A.
  static Uint8List _rgbaToArgb(Uint8List rgba) {
    final argb = Uint8List(rgba.length);
    for (var i = 0; i < rgba.length; i += 4) {
      argb[i] = rgba[i + 3];
      argb[i + 1] = rgba[i];
      argb[i + 2] = rgba[i + 1];
      argb[i + 3] = rgba[i + 2];
    }
    return argb;
  }
}

/// A square icon as ARGB32 bytes.
class _Pixmap {
  final int width;
  final int height;
  final Uint8List argb;

  const _Pixmap(this.width, this.height, this.argb);

  /// The `(iiay)` value of the StatusNotifierItem spec.
  DBusStruct toDBus() => DBusStruct([DBusInt32(width), DBusInt32(height), DBusArray.byte(argb)]);
}

/// The `org.kde.StatusNotifierItem` object the tray host reads the icon from.
class _StatusNotifierItem extends DBusObject {
  final String title;
  final List<_Pixmap> pixmaps;
  final Future<void> Function() onActivate;

  _StatusNotifierItem({required this.title, required this.pixmaps, required this.onActivate})
      : super(DBusObjectPath('/StatusNotifierItem'));

  /// The property values, keyed by name.
  Map<String, DBusValue> get _properties => {
        'Category': const DBusString('ApplicationStatus'),
        'Id': const DBusString('woxxy'),
        'Title': DBusString(title),
        'Status': const DBusString('Active'),
        'WindowId': const DBusUint32(0),
        'IconName': const DBusString(''),
        'IconPixmap': DBusArray(DBusSignature('(iiay)'), pixmaps.map((p) => p.toDBus())),
        'OverlayIconName': const DBusString(''),
        'OverlayIconPixmap': DBusArray(DBusSignature('(iiay)')),
        'AttentionIconName': const DBusString(''),
        'AttentionIconPixmap': DBusArray(DBusSignature('(iiay)')),
        'AttentionMovieName': const DBusString(''),
        'ToolTip': DBusStruct([
          const DBusString(''),
          DBusArray(DBusSignature('(iiay)')),
          DBusString(title),
          const DBusString(''),
        ]),
        'ItemIsMenu': const DBusBoolean(false),
        'Menu': DBusObjectPath('/MenuBar'),
      };

  @override
  List<DBusIntrospectInterface> introspect() {
    DBusIntrospectMethod positionMethod(String name) => DBusIntrospectMethod(name, args: [
          DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_, name: 'x'),
          DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_, name: 'y'),
        ]);

    return [
      DBusIntrospectInterface(
        LinuxTray._ITEM_INTERFACE,
        methods: [positionMethod('ContextMenu'), positionMethod('Activate'), positionMethod('SecondaryActivate')],
        properties: [
          for (final entry in _properties.entries)
            DBusIntrospectProperty(entry.key, entry.value.signature, access: DBusPropertyAccess.read),
        ],
      ),
    ];
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != LinuxTray._ITEM_INTERFACE) return DBusMethodErrorResponse.unknownInterface();

    switch (methodCall.name) {
      case 'Activate':
        zprint('🖱️ Tray icon clicked (left).');
        await onActivate();
        return DBusMethodSuccessResponse();
      case 'ContextMenu': // The host draws the dbusmenu itself
      case 'SecondaryActivate':
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != LinuxTray._ITEM_INTERFACE) return DBusMethodErrorResponse.unknownInterface();

    final value = _properties[name];
    if (value == null) return DBusMethodErrorResponse.unknownProperty();
    return DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != LinuxTray._ITEM_INTERFACE) return DBusMethodErrorResponse.unknownInterface();

    return DBusGetAllPropertiesResponse(_properties);
  }
}

/// The `com.canonical.dbusmenu` object with the tray menu: a flat list of entries (ids 1..n).
class _DBusMenu extends DBusObject {
  final List<LinuxTrayItem> items;

  _DBusMenu(this.items) : super(DBusObjectPath('/MenuBar'));

  /// The dbusmenu properties of the entry with [id].
  Map<String, DBusValue> _itemProperties(int id) {
    final item = items[id - 1];
    if (item.isSeparator) return {'type': const DBusString('separator')};
    return {'label': DBusString(item.label!), 'enabled': const DBusBoolean(true), 'visible': const DBusBoolean(true)};
  }

  /// The `(ia{sv}av)` layout node of the entry with [id].
  DBusStruct _itemNode(int id) =>
      DBusStruct([DBusInt32(id), DBusDict.stringVariant(_itemProperties(id)), DBusArray.variant([])]);

  @override
  List<DBusIntrospectInterface> introspect() {
    DBusIntrospectArgument arg(String type, DBusArgumentDirection direction, String name) =>
        DBusIntrospectArgument(DBusSignature(type), direction, name: name);

    return [
      DBusIntrospectInterface(
        LinuxTray._MENU_INTERFACE,
        methods: [
          DBusIntrospectMethod('GetLayout', args: [
            arg('i', DBusArgumentDirection.in_, 'parentId'),
            arg('i', DBusArgumentDirection.in_, 'recursionDepth'),
            arg('as', DBusArgumentDirection.in_, 'propertyNames'),
            arg('u', DBusArgumentDirection.out, 'revision'),
            arg('(ia{sv}av)', DBusArgumentDirection.out, 'layout'),
          ]),
          DBusIntrospectMethod('GetGroupProperties', args: [
            arg('ai', DBusArgumentDirection.in_, 'ids'),
            arg('as', DBusArgumentDirection.in_, 'propertyNames'),
            arg('a(ia{sv})', DBusArgumentDirection.out, 'properties'),
          ]),
          DBusIntrospectMethod('GetProperty', args: [
            arg('i', DBusArgumentDirection.in_, 'id'),
            arg('s', DBusArgumentDirection.in_, 'name'),
            arg('v', DBusArgumentDirection.out, 'value'),
          ]),
          DBusIntrospectMethod('Event', args: [
            arg('i', DBusArgumentDirection.in_, 'id'),
            arg('s', DBusArgumentDirection.in_, 'eventId'),
            arg('v', DBusArgumentDirection.in_, 'data'),
            arg('u', DBusArgumentDirection.in_, 'timestamp'),
          ]),
          DBusIntrospectMethod('AboutToShow', args: [
            arg('i', DBusArgumentDirection.in_, 'id'),
            arg('b', DBusArgumentDirection.out, 'needUpdate'),
          ]),
        ],
        properties: [
          DBusIntrospectProperty('Version', DBusSignature('u'), access: DBusPropertyAccess.read),
          DBusIntrospectProperty('TextDirection', DBusSignature('s'), access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Status', DBusSignature('s'), access: DBusPropertyAccess.read),
        ],
      ),
    ];
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != LinuxTray._MENU_INTERFACE) return DBusMethodErrorResponse.unknownInterface();

    switch (methodCall.name) {
      case 'GetLayout':
        final children = [for (var id = 1; id <= items.length; id++) DBusVariant(_itemNode(id))];
        final root = DBusStruct([
          const DBusInt32(0),
          DBusDict.stringVariant({'children-display': const DBusString('submenu')}),
          DBusArray.variant(children),
        ]);
        return DBusMethodSuccessResponse([const DBusUint32(1), root]);
      case 'GetGroupProperties':
        final ids = (methodCall.values[0] as DBusArray).children.map((v) => (v as DBusInt32).value);
        final properties = [
          for (final id in ids.where((id) => id >= 1 && id <= items.length))
            DBusStruct([DBusInt32(id), DBusDict.stringVariant(_itemProperties(id))]),
        ];
        return DBusMethodSuccessResponse([DBusArray(DBusSignature('(ia{sv})'), properties)]);
      case 'GetProperty':
        final id = (methodCall.values[0] as DBusInt32).value;
        final name = (methodCall.values[1] as DBusString).value;
        final value = id >= 1 && id <= items.length ? _itemProperties(id)[name] : null;
        if (value == null) return DBusMethodErrorResponse.invalidArgs('No property $name on menu item $id');
        return DBusMethodSuccessResponse([DBusVariant(value)]);
      case 'Event':
        final id = (methodCall.values[0] as DBusInt32).value;
        final eventId = (methodCall.values[1] as DBusString).value;
        if (eventId == 'clicked' && id >= 1 && id <= items.length) await items[id - 1].onClick?.call();
        return DBusMethodSuccessResponse();
      case 'AboutToShow':
        return DBusMethodSuccessResponse([const DBusBoolean(false)]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != LinuxTray._MENU_INTERFACE) return DBusMethodErrorResponse.unknownInterface();

    final value = _properties[name];
    if (value == null) return DBusMethodErrorResponse.unknownProperty();
    return DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != LinuxTray._MENU_INTERFACE) return DBusMethodErrorResponse.unknownInterface();

    return DBusGetAllPropertiesResponse(_properties);
  }

  /// The properties of the menu object itself.
  Map<String, DBusValue> get _properties => {
        'Version': const DBusUint32(3),
        'TextDirection': const DBusString('ltr'),
        'Status': const DBusString('normal'),
      };
}
