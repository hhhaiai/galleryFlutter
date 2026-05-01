import 'package:flutter/material.dart';

import '../features/gemma_home/gemma_home_screen.dart';

class GemmaLocalApp extends StatelessWidget {
  const GemmaLocalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gemma Local',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9D7DFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const GemmaHomeScreen(),
    );
  }
}
