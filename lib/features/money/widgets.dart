import 'package:flutter/material.dart';

import '../../core/constants.dart';
import 'models.dart';

/// Round colored avatar showing a category/account icon.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, this.iconName, this.color, this.size = 44});
  final String? iconName;
  final String? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Lookup.colorFromHex(color,
        fallback: Theme.of(context).colorScheme.primary);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Icon(Lookup.icon(iconName), color: c, size: size * 0.5),
    );
  }
}

/// Signed money text, colored green (income) / red (expense).
class AmountText extends StatelessWidget {
  const AmountText(this.text,
      {super.key, required this.positive, this.style});
  final String text;
  final bool positive;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: (style ?? Theme.of(context).textTheme.titleMedium)?.copyWith(
        color: positive ? const Color(0xFF2E9E5B) : const Color(0xFFE0533D),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Helper to pick an icon + color in editor sheets.
class IconColorPicker extends StatelessWidget {
  const IconColorPicker({
    super.key,
    required this.iconNames,
    required this.selectedIcon,
    required this.selectedColor,
    required this.onIcon,
    required this.onColor,
  });

  final List<String> iconNames;
  final String selectedIcon;
  final Color selectedColor;
  final ValueChanged<String> onIcon;
  final ValueChanged<Color> onColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Icon'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in iconNames)
              InkWell(
                onTap: () => onIcon(name),
                borderRadius: BorderRadius.circular(24),
                child: CircleAvatar(
                  backgroundColor: selectedIcon == name
                      ? selectedColor.withValues(alpha: 0.25)
                      : Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                  child: Icon(Lookup.icon(name),
                      color: selectedIcon == name ? selectedColor : null),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Color'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in Lookup.palette)
              InkWell(
                onTap: () => onColor(c),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selectedColor.toARGB32() == c.toARGB32()
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Standard sheet wrapper with a grabber + title + scrollable body.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

IconData txnTypeIcon(TxnType t) => switch (t) {
      TxnType.income => Icons.south_west,
      TxnType.expense => Icons.north_east,
      TxnType.transfer => Icons.swap_horiz,
    };
