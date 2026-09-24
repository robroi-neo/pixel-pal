import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GameScreen'),
        actions: [],
      )
    );
  }
}
