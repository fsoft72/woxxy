import 'package:flutter/material.dart';

/// Shows [message] in a snackbar of the nearest [Scaffold].
void showSnackbar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
    ),
  );
}
