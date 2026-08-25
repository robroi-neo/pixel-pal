import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Sign out',
            // GoRouter's redirect (see router/app_router.dart) sends the
            // user back to /login automatically once authStateChanges
            // fires — no navigation call needed here.
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: const Column(
        children: [

        ],
      ),
    );
  }
}
