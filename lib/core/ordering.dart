// Manual ordering with float sortOrder values (SPEC §5.1): never renumber a whole column.

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
