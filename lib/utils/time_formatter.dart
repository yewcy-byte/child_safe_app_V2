import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

class TimeFormatter {
  static String formatDetectionTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inHours < 1) {
      return timeago.format(timestamp, locale: 'en_short');
    } else if (difference.inDays < 1) {
      return DateFormat.jm().format(timestamp);
    } else if (difference.inDays < 365) {
      return DateFormat.MMMd().format(timestamp);
    } else {
      return DateFormat.yMMMd().format(timestamp);
    }
  }

  static String formatFullDateTime(DateTime timestamp) {
    return DateFormat.yMMMMd().add_jm().format(timestamp);
  }

  static String formatRelative(DateTime timestamp) {
    return timeago.format(timestamp);
  }

  static String formatTimeOnly(DateTime timestamp) {
    return DateFormat.jm().format(timestamp);
  }

  static String formatDateOnly(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToCheck = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (dateToCheck == today) {
      return 'Today';
    } else if (dateToCheck == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat.MMMd().format(timestamp);
    }
  }

  static bool isToday(DateTime timestamp) {
    final now = DateTime.now();
    return timestamp.year == now.year &&
        timestamp.month == now.month &&
        timestamp.day == now.day;
  }

  static bool isYesterday(DateTime timestamp) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return timestamp.year == yesterday.year &&
        timestamp.month == yesterday.month &&
        timestamp.day == yesterday.day;
  }
}
