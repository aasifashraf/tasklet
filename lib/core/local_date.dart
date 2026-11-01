/// A calendar date with no time or time zone, serialized as `YYYY-MM-DD` (SPEC §2.2).
class LocalDate implements Comparable<LocalDate> {
  LocalDate(this.year, this.month, this.day) {
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw FormatException('Invalid date: $year-$month-$day');
    }
  }

  /// The local calendar date of [dateTime] (converted to local time first).
  factory LocalDate.fromDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    return LocalDate(local.year, local.month, local.day);
  }

  static final _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static LocalDate parse(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) throw FormatException('Invalid date: $value');
    return LocalDate(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  static LocalDate? fromJson(Object? value) => switch (value) {
    null => null,
    final String s => parse(s),
    _ => throw FormatException('Invalid date: $value'),
  };

  final int year;
  final int month;
  final int day;

  DateTime get _utc => DateTime.utc(year, month, day);

  /// ISO weekday: Monday = 1 … Sunday = 7.
  int get weekday => _utc.weekday;

  LocalDate addDays(int days) {
    final d = _utc.add(Duration(days: days));
    return LocalDate(d.year, d.month, d.day);
  }

  /// Whole days from this date to [other] (positive when [other] is later).
  int daysUntil(LocalDate other) => other._utc.difference(_utc).inDays;

  /// Midnight at the start of this date in local time.
  DateTime toLocalDateTime() => DateTime(year, month, day);

  bool isBefore(LocalDate other) => compareTo(other) < 0;
  bool isAfter(LocalDate other) => compareTo(other) > 0;

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  String toJson() => toString();

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}
