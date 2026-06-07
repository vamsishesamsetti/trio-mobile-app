import 'package:flutter/material.dart';

/// Maps the icon-name strings stored in the DB to Material [IconData], plus
/// color helpers. Keeping this central means categories/accounts render the
/// same everywhere.
class Lookup {
  static const IconData _fallback = Icons.category_outlined;

  static const Map<String, IconData> _icons = {
    // expense / general
    'restaurant': Icons.restaurant,
    'shopping_cart': Icons.shopping_cart,
    'directions_car': Icons.directions_car,
    'shopping_bag': Icons.shopping_bag,
    'receipt': Icons.receipt_long,
    'movie': Icons.movie,
    'favorite': Icons.favorite,
    'home': Icons.home,
    'flight': Icons.flight,
    'category': Icons.category,
    // income
    'payments': Icons.payments,
    'work': Icons.work,
    'trending_up': Icons.trending_up,
    'card_giftcard': Icons.card_giftcard,
    'attach_money': Icons.attach_money,
    // accounts
    'wallet': Icons.account_balance_wallet,
    'bank': Icons.account_balance,
    'card': Icons.credit_card,
    'cash': Icons.payments,
    'savings': Icons.savings,
    // split categories
    'group': Icons.group,
    'fastfood': Icons.fastfood,
    'local_bar': Icons.local_bar,
    'hotel': Icons.hotel,
    'local_taxi': Icons.local_taxi,
    'sports_esports': Icons.sports_esports,
  };

  static IconData icon(String? name) => _icons[name] ?? _fallback;

  /// Picker options used in create/edit forms.
  static const List<String> categoryIconNames = [
    'restaurant', 'shopping_cart', 'directions_car', 'shopping_bag',
    'receipt', 'movie', 'favorite', 'home', 'flight', 'payments',
    'work', 'trending_up', 'card_giftcard', 'attach_money', 'category',
    'fastfood', 'local_bar', 'hotel', 'local_taxi', 'sports_esports',
  ];

  static const List<String> accountIconNames = [
    'wallet', 'bank', 'card', 'cash', 'savings',
  ];

  /// Palette offered in pickers + assigned round-robin to new items.
  static const List<Color> palette = [
    Color(0xFFEF5350), Color(0xFFEC407A), Color(0xFFAB47BC),
    Color(0xFF7E57C2), Color(0xFF5C6BC0), Color(0xFF42A5F5),
    Color(0xFF29B6F6), Color(0xFF26C6DA), Color(0xFF26A69A),
    Color(0xFF66BB6A), Color(0xFF9CCC65), Color(0xFFFFA726),
    Color(0xFFFF7043), Color(0xFF8D6E63), Color(0xFF78909C),
  ];

  static Color colorFromHex(String? hex, {Color fallback = const Color(0xFF78909C)}) {
    if (hex == null || hex.isEmpty) return fallback;
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }

  static String hexFromColor(Color c) {
    int ch(double v) => (v * 255).round() & 0xff;
    final r = ch(c.r), g = ch(c.g), b = ch(c.b);
    return '#${r.toRadixString(16).padLeft(2, '0')}'
            '${g.toRadixString(16).padLeft(2, '0')}'
            '${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }
}

/// Split expense categories (Splitwise feature) — fixed set with icons.
const Map<String, IconData> kSplitCategories = {
  'General': Icons.receipt_long,
  'Food & Drink': Icons.fastfood,
  'Groceries': Icons.shopping_cart,
  'Rent': Icons.home,
  'Utilities': Icons.bolt,
  'Transport': Icons.local_taxi,
  'Entertainment': Icons.sports_esports,
  'Travel': Icons.flight,
  'Lodging': Icons.hotel,
  'Drinks': Icons.local_bar,
};
