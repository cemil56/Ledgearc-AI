import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screens/main_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop (Windows/macOS/Linux) için FFI factory atamasını sadece burada bir defa yapıyoruz:
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();

    databaseFactory = databaseFactoryFfi;
  }

  runApp(const ProviderScope(child: LedgerArcApp()));
}

class LedgerArcApp extends StatelessWidget {
  const LedgerArcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LedgerArc AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
      ),
      home: const MainShell(),
    );
  }
}
