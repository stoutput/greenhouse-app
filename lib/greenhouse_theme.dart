import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'greenhouse_client.dart';

ThemeData greenhouseTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff4d9a7c),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xffa3e4c9) : const Color(0xff22664f),
        onPrimary: dark ? const Color(0xff10271f) : Colors.white,
        surface: dark ? const Color(0xff11191b) : const Color(0xffe6ede8),
        surfaceContainer: dark
            ? const Color(0xff1c2929)
            : const Color(0xfff4f8f4),
        onSurface: dark ? const Color(0xffedf5f1) : const Color(0xff182d27),
        onSurfaceVariant: dark
            ? const Color(0xffafc3bb)
            : const Color(0xff4a6157),
        outlineVariant: dark
            ? const Color(0xff374b46)
            : const Color(0xffc6d6cb),
      );
  final base = ThemeData(colorScheme: colors);
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -1.8,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.9,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SvgPicture.asset(
        'assets/greenhouse-mark.svg',
        width: 36,
        height: 36,
        excludeFromSemantics: true,
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          'GreenHouse',
          style: Theme.of(context).textTheme.titleLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      letterSpacing: 1.5,
      fontWeight: FontWeight.w700,
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: child,
    );
  }
}

String errorMessage(Object error) {
  if (error is GreenhouseException) return error.message;
  final message = error.toString().replaceFirst(
    RegExp(r'^(Exception|StateError|FormatException): '),
    '',
  );
  return message;
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
