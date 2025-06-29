class DateParser {
  // Extract date range from a query string
  DateTimeRange? extractDateRange(String query) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Simple date range extraction
    if (query.contains('today')) {
      return DateTimeRange(
        start: today,
        end: today.add(const Duration(days: 1)),
      );
    }

    if (query.contains('yesterday')) {
      final yesterday = today.subtract(const Duration(days: 1));
      return DateTimeRange(
        start: yesterday,
        end: today,
      );
    }

    if (query.contains('this week') || query.contains('week')) {
      final weekStart = today.subtract(Duration(days: today.weekday - 1));
      return DateTimeRange(
        start: weekStart,
        end: now,
      );
    }

    if (query.contains('this month') || query.contains('month')) {
      final monthStart = DateTime(today.year, today.month, 1);
      return DateTimeRange(
        start: monthStart,
        end: now,
      );
    }

    if (query.contains('last 7 days')) {
      return DateTimeRange(
        start: today.subtract(const Duration(days: 7)),
        end: now,
      );
    }

    if (query.contains('last 30 days')) {
      return DateTimeRange(
        start: today.subtract(const Duration(days: 30)),
        end: now,
      );
    }

    return null;
  }
}

class DateTimeRange {
  final DateTime start;
  final DateTime end;

  DateTimeRange({required this.start, required this.end});
}
