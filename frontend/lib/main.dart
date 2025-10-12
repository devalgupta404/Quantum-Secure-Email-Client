import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'providers/auth_provider.dart';
import 'app.dart';

void main() {
  // Initialize sqflite_common_ffi for desktop platforms (Windows, Linux, macOS)
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => AuthProvider(),
      child: const QuMailApp(),
    ),
  );
}
