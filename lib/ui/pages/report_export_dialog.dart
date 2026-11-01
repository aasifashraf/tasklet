import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local_date.dart';
import '../../core/models.dart';
import '../../core/report_charts.dart';
import '../../core/report_prompt.dart';
import '../../state/toast.dart';
import '../theme.dart';
import 'list_parts.dart';

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
      final extension = _kind == ReportKind.json ? 'json' : 'txt';
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Export report',
        fileName:
            'Tasklet ${_kind == ReportKind.json ? 'Report Data' : _kind.label} ${widget.today}.$extension',
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
              Text(
                'Export Report',
                style: TextStyles.section(context).copyWith(fontSize: 15),
              ),
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
                      'Chart preview',
                      style: TextStyles.sectionLabel(context),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() => _showCode = !_showCode),
                      child: Text(
                        _showCode ? 'Show charts' : 'Show Mermaid code',
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
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: _showCode
                          ? SelectableText(
                              _charts
                                  .map((c) => '```mermaid\n${c.mermaid}\n```')
                                  .join('\n\n'),
                              style: TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 11.5,
                                color: t.primary,
                                height: 1.4,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final (i, c) in _charts.indexed) ...[
                                  if (i > 0) const SizedBox(height: 18),
                                  _ChartPreview(chart: c),
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
class _ChartPreview extends StatelessWidget {
  const _ChartPreview({required this.chart});
  final ReportChart chart;

  Color _color(Tokens t, String label) {
    for (final s in TaskStatus.values) {
      if (s.label == label) {
        return s == TaskStatus.backlog
            ? t.tertiary.withValues(alpha: 0.45)
            : t.status(s);
      }
    }
    return t.accent;
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final max = chart.points.fold<num>(0, (m, p) => p.value > m ? p.value : m);
    final total = chart.points.fold<num>(0, (sum, p) => sum + p.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          chart.title,
          style: TextStyles.body(context).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        for (final p in chart.points)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    p.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.bodySecondary(context),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: max == 0
                            ? 0
                            : (constraints.maxWidth * p.value / max).clamp(
                                2.0,
                                constraints.maxWidth,
                              ),
                        height: 10,
                        decoration: BoxDecoration(
                          color: _color(t, p.label),
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    chart.kind == ChartKind.pie && total > 0
                        ? '${p.value}  ${(p.value * 100 / total).round()}%'
                        : '${p.value}',
                    textAlign: TextAlign.right,
                    style: TextStyles.meta(context)
                        .copyWith(color: t.secondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
