import 'package:intl/intl.dart';

/// Service for extracting temporal context from natural language queries
class TemporalContextExtractor {
  // Time-based regular expressions
  static final RegExp _timeRegex = RegExp(
      r'\b(?:at\s+)?'
      r'(?:(?:1[0-2]|0?[1-9])(?::[0-5][0-9])?\s*(?:am|pm)|'
      r'(?:[01]?[0-9]|2[0-3]):[0-5][0-9]|'
      r'(?:1[0-2]|0?[1-9])\s*(?:am|pm)|'
      r'(?:noon|midnight))\b',
      caseSensitive: false);

  // Date-based regular expressions
  static final RegExp _dateRegex = RegExp(
      r'\b(?:\d{1,2}[-/]\d{1,2}[-/]\d{2,4}|'
      r'\d{4}[-/]\d{1,2}[-/]\d{1,2}|'
      r'(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|'
      r'jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|'
      r'dec(?:ember)?)\s+\d{1,2}(?:st|nd|rd|th)?,?\s*\d{4}?)\b',
      caseSensitive: false);

  // Temporal modifiers
  static const List<String> _temporalModifiers = [
    'early',
    'late',
    'mid',
    'before',
    'after',
    'during',
    'around'
  ];

  // Base time terms
  static const List<String> _baseTimeTerms = [
    'morning',
    'afternoon',
    'evening',
    'night',
    'dawn',
    'dusk',
    'sunrise',
    'sunset'
  ];

  // Meal-based time references
  static const List<String> _mealTimeTerms = [
    'breakfast',
    'brunch',
    'lunch',
    'dinner',
    'supper'
  ];

  // Relative time terms
  static const List<String> _relativeTimeTerms = [
    'last',
    'latest',
    'recent',
    'previous',
    'next',
    'this',
    'coming'
  ];

  // Time period mapping (24-hour format)
  static const Map<String, Map<String, int>> _timePeriods = {
    'early_morning': {'start': 5, 'end': 8},
    'morning': {'start': 5, 'end': 12},
    'late_morning': {'start': 9, 'end': 12},
    'breakfast': {'start': 6, 'end': 10},
    'brunch': {'start': 10, 'end': 13},
    'lunch': {'start': 11, 'end': 14},
    'afternoon': {'start': 12, 'end': 17},
    'early_afternoon': {'start': 12, 'end': 14},
    'late_afternoon': {'start': 15, 'end': 17},
    'evening': {'start': 17, 'end': 21},
    'early_evening': {'start': 17, 'end': 19},
    'dinner': {'start': 18, 'end': 21},
    'late_evening': {'start': 19, 'end': 21},
    'night': {'start': 21, 'end': 5},
    'midnight': {'start': 0, 'end': 0},
    'dawn': {'start': 5, 'end': 7},
    'dusk': {'start': 17, 'end': 19}
  };

  /// Extract temporal context from a query string
  Map<String, dynamic> extractTemporalContext(String query) {
    final context = <String, dynamic>{
      'time_range': <String, dynamic>{},
      'date_range': <String, dynamic>{},
      'temporal_terms': <String>[],
      'confidence': 0.0
    };

    final queryLower = query.toLowerCase();
    var confidence = 0.0;

    // Extract explicit time references
    final timeMatches = _timeRegex.allMatches(queryLower);
    if (timeMatches.isNotEmpty) {
      final times =
          timeMatches.map((m) => _parseTimeString(m.group(0)!)).toList();
      if (times.isNotEmpty) {
        context['time_range'] = {
          'start': times.reduce((a, b) => a.isBefore(b) ? a : b),
          'end': times.reduce((a, b) => a.isAfter(b) ? a : b)
        };
        confidence += 0.3;
      }
    }

    // Extract explicit date references
    final dateMatches = _dateRegex.allMatches(queryLower);
    if (dateMatches.isNotEmpty) {
      final dates =
          dateMatches.map((m) => _parseDateString(m.group(0)!)).toList();
      if (dates.isNotEmpty) {
        context['date_range'] = {
          'start': dates.reduce((a, b) => a.isBefore(b) ? a : b),
          'end': dates.reduce((a, b) => a.isAfter(b) ? a : b)
        };
        confidence += 0.3;
      }
    }

    // Extract temporal terms and modifiers
    final terms = <String>[];

    // Check for temporal modifiers
    for (final modifier in _temporalModifiers) {
      if (queryLower.contains(modifier)) {
        terms.add(modifier);
        confidence += 0.1;
      }
    }

    // Check for base time terms
    for (final term in _baseTimeTerms) {
      if (queryLower.contains(term)) {
        terms.add(term);
        confidence += 0.1;
      }
    }

    // Check for meal-based time references
    for (final term in _mealTimeTerms) {
      if (queryLower.contains(term)) {
        terms.add(term);
        confidence += 0.1;

        // Add time range based on meal time if no explicit time is specified
        if (context['time_range'].isEmpty && _timePeriods.containsKey(term)) {
          final period = _timePeriods[term]!;
          context['time_range'] = {
            'start': DateTime(0, 1, 1, period['start']!),
            'end': DateTime(0, 1, 1, period['end']!)
          };
        }
      }
    }

    // Check for relative time terms
    for (final term in _relativeTimeTerms) {
      if (queryLower.contains(term)) {
        terms.add(term);
        confidence += 0.1;
      }
    }

    // Add extracted terms to context
    context['temporal_terms'] = terms;

    // Normalize confidence score to max of 1.0
    context['confidence'] = confidence.clamp(0.0, 1.0);

    return context;
  }

  /// Parse time string to DateTime object
  DateTime _parseTimeString(String timeStr) {
    timeStr = timeStr.toLowerCase().trim();

    // Handle special cases
    if (timeStr == 'noon') {
      return DateTime(0, 1, 1, 12, 0);
    }
    if (timeStr == 'midnight') {
      return DateTime(0, 1, 1, 0, 0);
    }

    try {
      // Try parsing various time formats
      final formats = ['h:mm a', 'hh:mm a', 'H:mm', 'HH:mm', 'h a', 'hh a'];

      for (final format in formats) {
        try {
          final time = DateFormat(format).parse(timeStr);
          return DateTime(0, 1, 1, time.hour, time.minute);
        } catch (_) {
          continue;
        }
      }

      // Default to current time if parsing fails
      return DateTime.now();
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Parse date string to DateTime object
  DateTime _parseDateString(String dateStr) {
    try {
      // Try parsing various date formats
      final formats = [
        'M/d/y',
        'MM/dd/yyyy',
        'd/M/y',
        'dd/MM/yyyy',
        'yyyy-MM-dd',
        'MMMM d, yyyy',
        'MMM d, yyyy'
      ];

      for (final format in formats) {
        try {
          return DateFormat(format).parse(dateStr);
        } catch (_) {
          continue;
        }
      }

      // Default to current date if parsing fails
      return DateTime.now();
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Get time period range from term
  Map<String, int>? getTimePeriodRange(String term) {
    final normalizedTerm = term.toLowerCase().replaceAll(' ', '_');
    return _timePeriods[normalizedTerm];
  }
}
