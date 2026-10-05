import 'package:flutter/material.dart';

/// Shows one of [children] at a time while keeping all of them mounted, so switching tabs
/// does not destroy their State (scroll position, text fields, stream subscriptions).
class PersistentTabs extends StatelessWidget {
  final int index;
  final List<Widget> children;

  const PersistentTabs({super.key, required this.index, required this.children});

  @override
  Widget build(BuildContext context) => IndexedStack(index: index, children: children);
}
