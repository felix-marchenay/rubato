import 'package:flutter/material.dart';

import 'library_screen.dart';
import 'theme.dart';

class RubatoApp extends StatelessWidget {
  const RubatoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rubato',
      debugShowCheckedModeBanner: false,
      theme: RubatoTheme.light(),
      darkTheme: RubatoTheme.dark(),
      home: const LibraryScreen(),
    );
  }
}
