import 'package:flutter/material.dart';

import '../screens/setup_screen.dart';

class BombanFutbolApp extends StatelessWidget {
  const BombanFutbolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bomban Futbol',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff00a86b),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff08140f),
        useMaterial3: true,
        fontFamily: 'Segoe UI',
      ),
      home: const SetupScreen(),
    );
  }
}
