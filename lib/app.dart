import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'state/prefs.dart';
import 'ui/theme.dart';

ThemeMode themeModeOf(ThemeChoice choice) => switch (choice) {
  ThemeChoice.auto => ThemeMode.system,
  ThemeChoice.light => ThemeMode.light,
  ThemeChoice.dark => ThemeMode.dark,
};

class TaskletApp extends ConsumerWidget {
  const TaskletApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(prefsProvider.select((p) => p.theme));
    return MaterialApp.router(
      title: 'Tasklet',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeModeOf(theme),
      routerConfig: appRouter,
    );
  }
}
