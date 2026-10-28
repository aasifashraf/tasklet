import 'package:flutter/material.dart';

void main() {
  runApp(const TaskletApp());
}

/// Placeholder root until the shell lands (ROADMAP milestone 2).
class TaskletApp extends StatelessWidget {
  const TaskletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Tasklet',
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: Text('Tasklet'))),
    );
  }
}
