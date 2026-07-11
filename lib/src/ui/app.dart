import 'package:flutter/material.dart';

import 'library_screen.dart';

class MscoreApp extends StatelessWidget {
  const MscoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3F51B5);
    return MaterialApp(
      title: 'mscore',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const LibraryScreen(),
    );
  }
}
