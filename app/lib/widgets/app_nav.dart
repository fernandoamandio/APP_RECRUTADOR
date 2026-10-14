import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Barra inferior: Vagas · Candidaturas · Perfil.
class AppNav extends StatelessWidget {
  const AppNav({super.key, required this.index});
  final int index;

  static const _routes = ['/feed', '/applications', '/profile'];

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (i) {
        if (i != index) context.go(_routes[i]);
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.work_outline), label: 'Vagas'),
        NavigationDestination(icon: Icon(Icons.task_alt), label: 'Candidaturas'),
        NavigationDestination(icon: Icon(Icons.person_outline), label: 'Perfil'),
      ],
    );
  }
}
