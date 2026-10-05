import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/widgets/persistent_tabs.dart';

class _Counter extends StatefulWidget {
  final String label;
  final List<String> log;
  const _Counter(this.label, this.log);

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  void initState() {
    super.initState();
    widget.log.add('init ${widget.label}');
  }

  @override
  void dispose() {
    widget.log.add('dispose ${widget.label}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => setState(() => taps++),
        child: Text('${widget.label}: $taps'),
      );
}

void main() {
  testWidgets('tab state survives switching tabs and screens are initialized once', (tester) async {
    final log = <String>[];
    Widget app(int index) => MaterialApp(
          home: PersistentTabs(index: index, children: [_Counter('A', log), _Counter('B', log)]),
        );

    await tester.pumpWidget(app(0));
    await tester.tap(find.text('A: 0'));
    await tester.pump();
    expect(find.text('A: 1'), findsOneWidget);

    await tester.pumpWidget(app(1));
    expect(find.text('B: 0'), findsOneWidget);
    expect(find.text('A: 1', skipOffstage: true), findsNothing);

    await tester.pumpWidget(app(0));
    expect(find.text('A: 1'), findsOneWidget);
    expect(log.where((l) => l.startsWith('dispose')), isEmpty);
    expect(log.where((l) => l == 'init A'), hasLength(1));
  });
}
