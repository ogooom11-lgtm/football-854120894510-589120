import 'package:flutter/material.dart';

import '../screens/setup_screen.dart';

class BombanFutbolApp extends StatelessWidget {
  const BombanFutbolApp({super.key});

  static const Color gold = Color(0xffd4af37);
  static const Color goldSoft = Color(0xfff5d67b);
  static const Color emerald = Color(0xff00c896);
  static const Color emeraldDeep = Color(0xff0a7d5a);
  static const Color background = Color(0xff050a08);
  static const Color surface = Color(0xff0b1512);
  static const Color surfaceRaised = Color(0xff11201a);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.dark(
      primary: emerald,
      onPrimary: const Color(0xff00130c),
      secondary: gold,
      onSecondary: const Color(0xff1a1300),
      surface: surface,
      onSurface: Colors.white,
      error: const Color(0xffff5c5c),
      onError: Colors.black,
      outline: Colors.white.withValues(alpha: 0.14),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bomban Futbol',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: background,
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        appBarTheme: AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: surface.withValues(alpha: 0.96),
          surfaceTintColor: Colors.transparent,
          titleTextStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
          iconTheme: const IconThemeData(color: Colors.white70),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: emerald, width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xffff5c5c)),
          ),
        ),
        dividerTheme: DividerThemeData(
          color: Colors.white.withValues(alpha: 0.07),
          thickness: 1,
        ),
        cardTheme: CardThemeData(
          color: surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: surfaceRaised,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: gold.withValues(alpha: 0.25)),
          ),
          titleTextStyle: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: surfaceRaised,
          contentTextStyle: const TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: gold.withValues(alpha: 0.35)),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white.withValues(alpha: 0.06),
          selectedColor: emerald.withValues(alpha: 0.25),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? emerald.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.04),
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? goldSoft
                  : Colors.white70,
            ),
            side: WidgetStatePropertyAll(
              BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: emeraldDeep,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: goldSoft,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: surfaceRaised,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: gold.withValues(alpha: 0.2)),
          ),
          textStyle: const TextStyle(color: Colors.white),
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: surfaceRaised,
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        listTileTheme: ListTileThemeData(
          iconColor: Colors.white70,
          textColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      home: const SetupScreen(),
    );
  }
}
