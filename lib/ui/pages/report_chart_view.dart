import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/report_charts.dart';
import '../theme.dart';

/// One report chart as horizontal bars (Reports page and the export preview).
class ReportChartView extends StatelessWidget {
  const ReportChartView({super.key, required this.chart});
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
                            right: Radius.circular(Radii.mark),
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
