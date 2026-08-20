import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets/companion_overlay.dart';

class GameMakerApp extends StatelessWidget {
  const GameMakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'Game Maker',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        builder: (context, child) {
          return CompanionScope(
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const HomeScreen(),
      ),
    );
  }
}
