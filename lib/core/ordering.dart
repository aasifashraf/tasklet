// Manual ordering with float sortOrder values (SPEC §5.1).

const double sortOrderGap = 1000;

/// A sortOrder that sorts between [before] (the card above) and [after] (the card below).
/// Either may be null at an end of the list; both null means an empty list.
double sortOrderBetween(double? before, double? after) {
  if (before == null && after == null) return 0;
  if (before == null) return after! - sortOrderGap;
  if (after == null) return before + sortOrderGap;
  return before + (after - before) / 2;
}

/// A sortOrder that places a task above every task in [existing] (manual order is ascending).
double sortOrderAtTop(Iterable<double> existing) {
  if (existing.isEmpty) return 0;
  return existing.reduce((a, b) => a < b ? a : b) - sortOrderGap;
}

/// Where a card dropped at [index] of [column] (the column's sortOrders in display order, without the card) goes.
///
/// Normally only the card moves, to the midpoint of its neighbours (SPEC §5.1). When the neighbours share a value
/// (common: many tasks at 0) or are too close for a distinct double, the midpoint wouldn't sort between them and the
/// card would land by tie-break instead of where it was dropped. Then the smallest run of neighbouring cards around
/// the drop point is re-spaced evenly together with the card.
///
/// Returns the card's new value and the new values of re-spaced cards by their index in [column].
({double value, Map<int, double> respaced}) placeInColumn(
  List<double> column,
  int index,
) {
  final before = index > 0 ? column[index - 1] : null;
  final after = index < column.length ? column[index] : null;
  final mid = sortOrderBetween(before, after);
  if ((before == null || mid > before) && (after == null || mid < after)) {
    return (value: mid, respaced: const {});
  }

  // The window column[lo..hi) is re-spaced together with the card, which sits between column[index - 1] and
  // column[index]. Widen it one card per side (and over runs of equal values at its edges) until the values just
  // outside leave room; with both ends open there is always room, so this terminates.
  var lo = index, hi = index;
  while (true) {
    if (lo > 0) lo--;
    if (hi < column.length) hi++;
    while (lo > 0 && column[lo - 1] == column[lo]) {
      lo--;
    }
    while (hi < column.length && column[hi] == column[hi - 1]) {
      hi++;
    }
    final values = _spread(
      lo > 0 ? column[lo - 1] : null,
      hi < column.length ? column[hi] : null,
      hi - lo + 1,
    );
    if (values == null) continue;
    return (
      value: values[index - lo],
      respaced: {
        for (var i = lo; i < index; i++) i: values[i - lo],
        for (var i = index; i < hi; i++) i: values[i - lo + 1],
      },
    );
  }
}

/// [count] strictly increasing values strictly between [low] and [high] (either may be null for open-ended), or
/// null when doubles can't fit them.
List<double>? _spread(double? low, double? high, int count) {
  final List<double> values;
  if (low == null && high == null) {
    values = [for (var i = 0; i < count; i++) i * sortOrderGap];
  } else if (low == null) {
    values = [for (var i = count; i > 0; i--) high! - i * sortOrderGap];
  } else if (high == null) {
    values = [for (var i = 1; i <= count; i++) low + i * sortOrderGap];
  } else {
    final step = (high - low) / (count + 1);
    values = [for (var i = 1; i <= count; i++) low + i * step];
  }
  var previous = low;
  for (final v in values) {
    if (!v.isFinite || (previous != null && v <= previous)) return null;
    previous = v;
  }
  if (high != null && values.last >= high) return null;
  return values;
}
