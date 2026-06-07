import 'package:intl/intl.dart';

/// Currency, date, and duration formatting helpers shared across features.
class Fmt {
  /// Minimal symbol table; falls back to the code itself for anything else.
  static const Map<String, String> _symbols = {
    'USD': '\$', 'EUR': '€', 'GBP': '£', 'INR': '₹', 'JPY': '¥',
    'CAD': 'CA\$', 'AUD': 'A\$', 'CHF': 'CHF ', 'CNY': '¥', 'AED': 'د.إ ',
  };

  static String symbol(String currency) => _symbols[currency] ?? '$currency ';

  /// e.g. money(1234.5, 'USD') -> "$1,234.50"
  static String money(num amount, String currency, {bool sign = false}) {
    final f = NumberFormat.currency(
      symbol: symbol(currency),
      decimalDigits: 2,
    );
    final formatted = f.format(amount.abs());
    if (sign) {
      final prefix = amount < 0 ? '-' : '+';
      return '$prefix$formatted';
    }
    return amount < 0 ? '-$formatted' : formatted;
  }

  /// Compact form for chart axis labels, e.g. 12.3K.
  static String compact(num amount, String currency) =>
      '${symbol(currency)}${NumberFormat.compact().format(amount)}';

  static String dateShort(DateTime d) => DateFormat('MMM d').format(d);
  static String dateMedium(DateTime d) => DateFormat('MMM d, y').format(d);
  static String dateFull(DateTime d) => DateFormat('EEE, MMM d, y').format(d);
  static String monthYear(DateTime d) => DateFormat('MMMM y').format(d);
  static String time(DateTime d) => DateFormat('h:mm a').format(d);
  static String dateTime(DateTime d) => DateFormat('MMM d, h:mm a').format(d);

  /// Seconds -> "2h 05m" (hours tracker) and "2:05:09" (live timer).
  static String hm(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  static String clock(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// Decimal hours, e.g. 2.5 for 2h30m.
  static double decimalHours(int seconds) => seconds / 3600.0;
}
