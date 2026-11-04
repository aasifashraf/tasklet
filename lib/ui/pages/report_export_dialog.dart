import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local_date.dart';
import '../../core/report_charts.dart';
import '../../core/report_prompt.dart';
import '../../state/toast.dart';
import '../theme.dart';
import 'list_parts.dart';
import 'report_chart_view.dart';

/// Export the report as a text file (SPEC §4.9): pick the format, preview the charts, choose whether to include
/// them as Mermaid, then save where the user chooses. Copy to Clipboard stays available.
Future<void> showReportExportDialog(
  BuildContext context, {
  required Map<String, Object?> json,
  required int taskCount,
  required LocalDate today,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ExportDialog(json: json, taskCount: taskCount, today: today),
);

class _ExportDialog extends ConsumerStatefulWidget {
  const _ExportDialog({
    required this.json,
    required this.taskCount,
    required this.today,
  });
  final Map<String, Object?> json;
  final int taskCount;
  final LocalDate today;

  @override
  ConsumerState<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<_ExportDialog> {
  ReportKind _kind = ReportKind.report;
  bool _includeCharts = true;
  bool _showCode = false;
  bool _saving = false;
  late final List<ReportChart> _charts = chartsForReport(widget.json);

  bool get _chartsAllowed => _kind != ReportKind.json && _charts.isNotEmpty;

  String _text() => buildReportText(
    _kind,
    widget.json,
    charts: _chartsAllowed && _includeCharts ? _charts : const [],
  );

  String get _tasks =>
      '${widget.taskCount} ${widget.taskCount == 1 ? 'task' : 'tasks'}';

  Future<void> _export() async {
    setState(() => _saving = true);
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Export report',
        fileName: reportFileName(_kind, widget.json),
        bytes: Uint8List.fromList(utf8.encode(_text())),
      );
      if (uri == null || !mounted) return;
      final name = uri.pathSegments.isEmpty
          ? uri.toString()
          : Uri.decodeComponent(uri.pathSegments.last);
      ref.read(toastProvider.notifier).show('Exported $name ($_tasks)');
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text()));
    ref.read(toastProvider.notifier).show('Copied ${_kind.label} ($_tasks)');
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Export Report', style: TextStyles.pageTitle(context)),
              const SizedBox(height: 4),
              Text('Covers $_tasks.', style: TextStyles.bodySecondary(context)),
              const SizedBox(height: 16),
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Format',
                      style: TextStyles.sectionLabel(context),
                    ),
                  ),
                  PillToggle<ReportKind>(
                    options: {for (final k in ReportKind.values) k: k.label},
                    selected: _kind,
                    onChanged: (k) => setState(() => _kind = k),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 90),
                  Checkbox(
                    value: _chartsAllowed && _includeCharts,
                    onChanged: _chartsAllowed
                        ? (v) => setState(() => _includeCharts = v ?? false)
                        : null,
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      _kind == ReportKind.json
                          ? 'Mermaid charts are only added to prompts (JSON Only stays pure JSON).'
                          : _charts.isEmpty
                          ? 'There is nothing to chart for this selection.'
                          : 'Include Mermaid charts in the exported file',
                      style: TextStyles.body(context)
                          .copyWith(color: _chartsAllowed ? null : t.tertiary),
                    ),
                  ),
                ],
              ),
              if (_charts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Chart Preview',
                      style: TextStyles.sectionLabel(context),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() => _showCode = !_showCode),
                      child: Text(
                        _showCode ? 'Show Charts' : 'Show Mermaid Code',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                      color: t.surface,
                      border: Border.all(color: t.border),
                      borderRadius: BorderRadius.circular(Radii.medium),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: _showCode
                          ? SelectableText(
                              _charts
                                  .map((c) => '```mermaid\n${c.mermaid}\n```')
                                  .join('\n\n'),
                              style: TextStyles.code(context),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final (i, c) in _charts.indexed) ...[
                                  if (i > 0) const SizedBox(height: 18),
                                  ReportChartView(chart: c),
                                ],
                              ],
                            ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _saving ? null : _copy,
                    child: const Text('Copy to Clipboard'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _export,
                    icon: const Icon(Icons.download, size: 15),
                    label: Text(_saving ? 'Saving…' : 'Export…'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontal bar per value, labelled directly (thin marks, rounded data ends, text in text colors).
