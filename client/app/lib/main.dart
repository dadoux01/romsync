import 'package:flutter/material.dart';

void main() {
  runApp(const RomSyncApp());
}

/// Root widget of the RomSync desktop client.
class RomSyncApp extends StatelessWidget {
  const RomSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RomSync',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4F6DF5)),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF4F6DF5), brightness: Brightness.dark),
      home: const Scaffold(body: Center(child: Text('RomSync'))),
    );
  }
}
