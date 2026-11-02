import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/app.dart';
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/organization.dart';
import 'package:tasklet/data/prefs_store.dart';
import 'package:tasklet/data/workspace_store.dart';
import 'package:tasklet/state/boards.dart';
import 'package:tasklet/state/prefs.dart';
import 'package:tasklet/state/ui_state.dart';
import 'package:tasklet/state/workspace.dart';
import 'package:tasklet/ui/organizations.dart';

import '../helpers.dart';
import 'app_flow_test.dart' show settle;

/// Switching organizations (docs/DECISIONS.md D15) shows the other folder and starts its session fresh.
void main() {
  testWidgets('the sidebar switcher opens the other organization', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final root = Directory.systemTemp.createTempSync('tasklet_orgs_');
    addTearDown(() => root.deleteSync(recursive: true));
    final work = p.join(root.path, 'Work'), oss = p.join(root.path, 'OSS');
    final prefs = await tester.runAsync(() async {
      for (final (folder, info, name) in [
        (work, const OrgInfo(name: 'Acme Corp'), 'Billing API'),
        (
          oss,
          const OrgInfo(name: 'Open Source', color: TaskletColor.green),
          'Tasklet Plugin',
        ),
      ]) {
        Directory(folder).createSync();
        await WorkspaceStore.initialize(folder, organization: info);
        final store = WorkspaceStore(folder);
        await store.read();
        await store.writeProject(
          project(name.toLowerCase().replaceAll(' ', '-'), name: name),
        );
      }
      final prefs = await PrefsStore.open(p.join(root.path, 'prefs.json'));
      await prefs.set(PrefKeys.dataFolder, work);
      return prefs;
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [prefsStoreProvider.overrideWithValue(prefs!)],
          child: const TaskletApp(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TaskletApp)),
    );

    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Billing API'), findsWidgets);
    // Opening it once lists it on this computer.
    expect(prefs!.values[PrefKeys.organizations], isNotNull);

    // Add the second one, then leave some session state behind in the first.
    await tester.runAsync(
      () => container
          .read(workspaceProvider.notifier)
          .addOrganization(oss)
          .then(
            (_) => container
                .read(workspaceProvider.notifier)
                .switchOrganization(work),
          ),
    );
    await settle(tester);
    container.read(sessionSearchProvider.notifier).set('all', 'billing');
    container
        .read(openTaskProvider.notifier)
        .open(const TaskRef('billing-api', 'nope'));

    await tester.tap(find.byType(OrganizationSwitcher));
    await tester.pumpAndSettle();
    expect(find.text('Open Source'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Open Source'));
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await settle(tester, rounds: 40);

    expect(find.text('Tasklet Plugin'), findsWidgets);
    expect(find.text('Billing API'), findsNothing);
    expect(container.read(sessionSearchProvider), isEmpty);
    expect(container.read(openTaskProvider), isNull);
    final orgs = container.read(prefsProvider).organizations;
    expect([for (final o in orgs) o.info.name], ['Acme Corp', 'Open Source']);
    expect(container.read(prefsProvider).dataFolder, oss);

    // Close the app so its folder watcher lets go of the temp folders.
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
  });
}
