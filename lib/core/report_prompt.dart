import 'dart:convert';

import 'package:intl/intl.dart';

import 'local_date.dart';
import 'report_charts.dart';

/// What the Reports Copy button produces (SPEC §4.9).
enum ReportKind {
  report('Report Prompt'),
  summary('Summary Prompt'),
  json('JSON Only');

  const ReportKind(this.label);
  final String label;
}

final _human = DateFormat('MMM d, y');

String _humanDate(String ymd) =>
    _human.format(LocalDate.parse(ymd).toLocalDateTime());

/// Builds the export text for [kind] from the report JSON. With [charts], ready-made Mermaid charts are included
/// before the data (prompts only; JSON Only stays pure JSON).
String buildReportText(
  ReportKind kind,
  Map<String, Object?> json, {
  List<ReportChart> charts = const [],
}) {
  final pretty = const JsonEncoder.withIndent('  ').convert(json);
  if (kind == ReportKind.json) return pretty;

  final report = json['report']! as Map<String, Object?>;
  final period = report['period']! as Map<String, Object?>;
  final hasTimeline = json.containsKey('timeline');
  final hasFilters = report.containsKey('filters');
  final totals = (json['totals'] as Map<String, Object?>?) ?? const {};
  final projectCount = (json['projects'] as List<Object?>?)?.length ?? 0;
  final usesLabels = totals.containsKey('byLabel');
  final completedAfter = totals.containsKey('completedAfterPeriod');
  final timelineKinds = [
    if ((json['timeline'] as Map<String, Object?>?)?.containsKey('months') ??
        false)
      'month',
    if ((json['timeline'] as Map<String, Object?>?)?.containsKey('weeks') ??
        false)
      'week',
  ];

  final b = StringBuffer()
    ..writeln(
      'Below is task data from my personal task tracker covering ${period['name']} '
      '(${_humanDate(period['from']! as String)} to ${_humanDate(period['to']! as String)}).',
    )
    ..writeln()
    ..writeln('How to read the data:')
    ..writeln(
      '- "report.today" is today\'s date; "report.period" is the date range this report covers (inclusive).',
    )
    ..writeln(
      '- A task is included if it overlapped the period in any way: it was open at some point during it, was '
      'completed during it, or its start or due date fell inside it.',
    )
    ..writeln(
      '- "atPeriodEnd" and "inPeriod" describe the task during the period: whether it was done, still open, or not '
      'created yet when the period ended, and which events (created, started, due, completed) happened inside it. '
      '"statusNow" is its status today, which may differ.',
    )
    ..writeln(
      '- All numbers under "totals" (and each project\'s "totals") are already calculated. Use them exactly as '
      'given; do not recount or estimate.',
    );
  if (hasTimeline) {
    b.writeln(
      '- "timeline" breaks the period into ${timelineKinds.join(' and ')} buckets. Each bucket counts tasks created, '
      'completed and due inside it, and "openAtEnd" is how many were still open when that bucket ended.',
    );
  }
  if (hasFilters) {
    b.writeln(
      '- The report was filtered as listed in "report.filters". Anything not listed there was not filtered.',
    );
  }
  b
    ..writeln('- Fields that are empty or zero are left out.')
    ..writeln()
    ..writeln('Writing rules:')
    ..writeln(
      '- Write for someone who has never seen this data or this app. Use plain language.',
    )
    ..writeln(
      '- Never mention internal field names or show raw JSON. Write dates like "Sep 12", never "2026-09-12".',
    )
    ..writeln(
      '- Be factual. Never invent numbers, tasks, or reasons that are not in the data.',
    )
    ..writeln()
    ..writeln('Visuals first:')
    ..writeln(
      '- If you can render charts or artifacts, lead with them before any text. Otherwise use Mermaid pie or bar '
      'charts. If neither works, use simple text bars (for example "Done ████████ 10").',
    )
    ..writeln();

  if (kind == ReportKind.summary) {
    b
      ..writeln('Please write a short summary:')
      ..writeln('1. One small visual of the most important numbers.')
      ..writeln('2. One or two sentences on overall progress.')
      ..writeln(
        '3. Four to seven bullet points on what matters most: notable completions, work in flight, anything '
        'overdue or at risk, and standout projects.',
      );
    if (hasTimeline) {
      b.writeln('4. One sentence about the trend over the period.');
    }
    if (completedAfter) {
      b.writeln(
        '- Mention briefly that some tasks open at the end of the period have been completed since.',
      );
    }
    b.writeln('Keep it under 200 words, with no headings and no tables.');
  } else {
    b
      ..writeln('Please write a full report in Markdown:')
      ..writeln('- A title, then the visuals.')
      ..writeln('- Then these numbered sections:')
      ..writeln('  1. Overview')
      ..writeln('  2. Key numbers (as a table)');
    var n = 3;
    if (hasTimeline) {
      final unit = timelineKinds.contains('month')
          ? 'Month-by-month'
          : 'Week-by-week';
      b.writeln(
        '  ${n++}. $unit breakdown${timelineKinds.length == 2 ? ' (with a short weekly breakdown for busy months)' : ''}',
      );
    }
    b
      ..writeln(
        '  ${n++}. Completed in the period${projectCount > 1 ? ' (grouped by project)' : ''}',
      )
      ..writeln('  ${n++}. Still open at period end')
      ..writeln(
        '  ${n++}. Risks & blockers (today\'s overdue and urgent items, and why they matter)',
      );
    if (projectCount > 1) b.writeln('  ${n++}. By project');
    if (usesLabels) b.writeln('  ${n++}. By label');
    b
      ..writeln('  ${n++}. Next steps (3–6 concrete recommendations)')
      ..writeln('- If a section has nothing to report, write "None."');
  }

  if (charts.isNotEmpty) {
    b
      ..writeln()
      ..writeln(
        'Ready-made charts (Mermaid), drawn from the same data. Show them as they are, or redraw them, before',
      )
      ..writeln('the text:');
    for (final chart in charts) {
      b
        ..writeln()
        ..writeln('```mermaid')
        ..writeln(chart.mermaid)
        ..writeln('```');
    }
  }

  b
    ..writeln()
    ..writeln('```json')
    ..writeln(pretty)
    ..writeln('```');
  return b.toString();
}
