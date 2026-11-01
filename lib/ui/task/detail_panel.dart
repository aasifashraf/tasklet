import 'package:flutter/material.dart';

import '../../state/ui_state.dart';

/// The right-side task detail sheet (filled in by milestone 5).
class DetailPanelOverlay extends StatelessWidget {
  const DetailPanelOverlay({super.key, required this.taskRef});
  final TaskRef taskRef;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
