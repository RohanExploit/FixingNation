import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: CivicPulseApp()));
}

class CivicPulseApp extends StatelessWidget {
  const CivicPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CivicPulse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C3BFF), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('CivicPulse MVP scaffold ready'),
        ),
      ),
    );
  }
}
