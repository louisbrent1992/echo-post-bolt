import '../services/media_search_service.dart';

class DateParser {
  // Extract a date range from a query string
  DateTimeRange? extractDateRange(String query) {
    final now = DateTime.now();
    
    // Check for "yesterday"
    if (query.contains('yesterday')) {
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      return DateTimeRange(
        start: DateTime(yesterday.year, yesterday.month, yesterday.day, 0, 0),
        end: DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59),
      );
    }
    
    // Check for "last week"
    if (query.contains('last week')) {
      final weekAgo = now.subtract(const Duration(days: 7));
      return DateTimeRange(
        start: weekAgo,
        end: now,
      );
    }
    
    // Check for "last month"
    if (query.contains('last month')) {
      final monthAgo = DateTime(now.year, now.month - 1, now.day);
      return DateTimeRange(
        start: monthAgo,
        end: now,
      );
    }
    
    // Check for "today"
    if (query.contains('today')) {
      return DateTimeRange(
        start: DateTime(now.year, now.month, now.day, 0, 0),
        end: now,
      );
    }
    
    // Check for "this week"
    if (query.contains('this week')) {
      // Find the start of the week (Sunday)
      final daysToSubtract = now.weekday % 7;
      final startOfWeek = now.subtract(Duration(days: daysToSubtract));
      return DateTimeRange(
        start: DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day, 0, 0),
        end: now,
      );
    }
    
    // Check for "this month"
    if (query.contains('this month')) {
      return DateTimeRange(
        start: DateTime(now.year, now.month, 1, 0, 0),
        end: now,
      );
    }
    
    // Check for "last year"
    if (query.contains('last year')) {
      return DateTimeRange(
        start: DateTime(now.year - 1, 1, 1, 0, 0),
        end: DateTime(now.year - 1, 12, 31, 23, 59, 59),
      );
    }
    
    // Check for specific dates (simplified)
    // In a real app, you'd use a more sophisticated date parser
    final dateRegex = RegExp(r'(\d{1,2})[\/\-](\d{1,2})(?:[\/\-](\d{2,4}))?');
    final match = dateRegex.firstMatch(query);
    if (match != null) {
      int day = int.parse(match.group(1)!);
      int month = int.parse(match.group(2)!);
      int year = int.parse(match.group(3) ?? now.year.toString());
      
      // Adjust 2-digit year
      if (year < 100) {
        year += 2000;
      }
      
      try {
        final date = DateTime(year, month, day);
        return DateTimeRange(
          start: DateTime(date.year, date.month, date.day, 0, 0),
          end: DateTime(date.year, date.month, date.day, 23, 59, 59),
        );
      } catch (e) {
        // Invalid date, ignore
      }
    }
    
    // Default: return null if no date range found
    return null;
  }
}