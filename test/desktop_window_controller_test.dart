import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/bootstrap/desktop_window_controller.dart';

class _FakeWindow implements DesktopWindow {
  final List<String> calls = [];
  bool visible = true;

  @override
  Future<void> hide() async {
    calls.add('hide');
    visible = false;
  }

  @override
  Future<bool> isVisible() async => visible;

  @override
  Future<void> show() async {
    calls.add('show');
    visible = true;
  }

  @override
  Future<void> focus() async => calls.add('focus');

  @override
  Future<void> popUpTrayMenu() async => calls.add('menu');
}

void main() {
  late _FakeWindow window;
  late DesktopWindowController controller;

  setUp(() {
    window = _FakeWindow();
    controller = DesktopWindowController(window: window);
  });

  test('closing the window only hides it', () async {
    controller.onWindowClose();
    await Future<void>.delayed(Duration.zero);

    expect(window.calls, ['hide']);
  });

  test('a tray click shows a hidden window and focuses it', () async {
    window.visible = false;

    controller.onTrayIconMouseDown();
    await Future<void>.delayed(Duration.zero);

    expect(window.calls, ['show', 'focus']);
  });

  test('a tray click only focuses a window that is already visible', () async {
    controller.onTrayIconMouseDown();
    await Future<void>.delayed(Duration.zero);

    expect(window.calls, ['focus']);
  });

  test('a right click opens the tray menu', () {
    controller.onTrayIconRightMouseDown();

    expect(window.calls, ['menu']);
  });
}
