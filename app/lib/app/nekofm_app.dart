import 'package:flutter/material.dart';

import '../features/shell/app_shell.dart';

class NekoFmApp extends StatelessWidget {
  const NekoFmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NekoFM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff1f8a70),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff101413),
      ),
      home: const AppShell(),
    );
  }
}
