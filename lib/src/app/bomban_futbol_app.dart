import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/setup_screen.dart';

class BombanFutbolApp extends StatelessWidget {
  const BombanFutbolApp({super.key});

  static const Color gold = Color(0xffd4af37);
  static const Color goldSoft = Color(0xfff5d67b);
  static const Color emerald = Color(0xff00c896);
  static const Color emeraldDeep = Color(0xff0a7d5a);
  static const Color emeraldDark = Color(0xff063d2e);
  static const Color background = Color(0xff040b09);
  static const Color surface = Color(0xff0b1512);
  static const Color surfaceRaised = Color(0xff11201b);
  static const Color danger = Color(0xffff5c5c);

  /// Decoration shared by the big panels of the app.
  static BoxDecoration panelDecoration({
    Color accent = gold,
    double radius = 16,
  }) {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff14251f), Color(0xff0d1a16), Color(0xff0a1411)],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: accent.withValues(alpha: 0.20), width: 1),
      boxShadow: const [
        BoxShadow(
          color: Colors.black54,
          blurRadius: 22,
          offset: Offset(0, 10),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.dark(
      primary: emerald,
      onPrimary: const Color(0xff00130c),
      secondary: gold,
      onSecondary: const Color(0xff1a1300),
      surface: surface,
      onSurface: Colors.white,
      error: danger,
      onError: Colors.black,
      outline: Colors.white.withValues(alpha: 0.14),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bomban Futbol',
      // Keep very large / very small system font settings usable.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.15,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: background,
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        appBarTheme: AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: const Color(0xff0a1713),
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black45,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          shape: Border(
            bottom: BorderSide(
              color: gold.withValues(alpha: 0.24),
              width: 1.2,
            ),
          ),
          titleTextStyle: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 0.4,
          ),
          iconTheme: const IconThemeData(color: goldSoft),
          actionsIconTheme: const IconThemeData(color: goldSoft),
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
          titleMedium: TextStyle(fontWeight: FontWeight.w800),
          titleSmall: TextStyle(fontWeight: FontWeight.w700),
          labelLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3),
          bodyMedium: TextStyle(height: 1.35),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.055),
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: _inputBorder(Colors.white12),
          enabledBorder: _inputBorder(
            Colors.white.withValues(alpha: 0.13),
          ),
          focusedBorder: _inputBorder(emerald, width: 1.6),
          errorBorder: _inputBorder(danger),
          focusedErrorBorder: _inputBorder(danger, width: 1.6),
        ),
        dividerTheme: DividerThemeData(
          color: Colors.white.withValues(alpha: 0.08),
          thickness: 1,
        ),
        cardTheme: CardThemeData(
          color: surface,
          surfaceTintColor: Colors.transparent,
          elevation: 4,
          shadowColor: Colors.black54,
          margin: const EdgeInsets.all(6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: surfaceRaised,
          surfaceTintColor: Colors.transparent,
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: gold.withValues(alpha: 0.28)),
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
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: gold.withValues(alpha: 0.38)),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white.withValues(alpha: 0.07),
          selectedColor: emerald.withValues(alpha: 0.28),
          labelStyle: const TextStyle(color: Colors.white),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? emerald.withValues(alpha: 0.24)
                  : Colors.white.withValues(alpha: 0.045),
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? goldSoft
                  : Colors.white70,
            ),
            side: WidgetStatePropertyAll(
              BorderSide(color: Colors.white.withValues(alpha: 0.13)),
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: emeraldDark,
            foregroundColor: Colors.white,
            elevation: 2,
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: goldSoft,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: Colors.white70,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: surfaceRaised,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: gold.withValues(alpha: 0.22)),
          ),
          textStyle: const TextStyle(color: Colors.white),
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: surfaceRaised,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: gold.withValues(alpha: 0.2)),
          ),
          textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        listTileTheme: ListTileThemeData(
          iconColor: Colors.white70,
          textColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: emerald,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.14),
          thumbColor: goldSoft,
          overlayColor: emerald.withValues(alpha: 0.18),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? emerald
                : Colors.white.withValues(alpha: 0.08),
          ),
          checkColor: WidgetStateProperty.all(const Color(0xff00130c)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? goldSoft
                : Colors.white70,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? emerald.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: emerald,
          linearTrackColor: Color(0x1affffff),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(
            Colors.white.withValues(alpha: 0.22),
          ),
          radius: const Radius.circular(8),
          thickness: WidgetStateProperty.all(7),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: surfaceRaised,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
        ),
      ),
      home: const SetupScreen(),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
