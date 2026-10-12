import 'package:flutter/material.dart';

const kMaroon = Color(0xFF4A1B0C);
const kClay = Color(0xFF993C1D);
const kSaffron = Color(0xFFEF9F27);
const kCream = Color(0xFFFFF8EC);
const kLine = Color(0xFFE8C99A);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kClay).copyWith(
    primary: kClay,
    secondary: kSaffron,
  );
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: w),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kCream,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: border(kLine),
      enabledBorder: border(kLine),
      focusedBorder: border(kClay, 1.5),
      errorBorder: border(Colors.red.shade700),
      focusedErrorBorder: border(Colors.red.shade700, 1.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kSaffron,
        foregroundColor: kMaroon,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kClay,
        minimumSize: const Size.fromHeight(46),
        side: const BorderSide(color: kClay),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

/// Maroon banner at the top of a screen.
class Header extends StatelessWidget {
  const Header({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: kMaroon,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Om namo venkatesaya',
                    style: TextStyle(color: kSaffron, fontSize: 13)),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    color: Color(0xFFFAEEDA),
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    height: 1.2)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!,
                  style:
                      const TextStyle(color: Color(0xFFF5C4B3), fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

/// White rounded card with a thin saffron border.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLine),
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: kClay, fontSize: 14, fontWeight: FontWeight.w600)),
      );
}
