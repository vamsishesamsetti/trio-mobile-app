import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom-navigation scaffold wrapping the five top-level tabs. Uses
/// [StatefulNavigationShell] so each tab keeps its own navigation state.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    (icon: Icons.dashboard_outlined, selected: Icons.dashboard, label: 'Home'),
    (icon: Icons.account_balance_wallet_outlined, selected: Icons.account_balance_wallet, label: 'Money'),
    (icon: Icons.groups_outlined, selected: Icons.groups, label: 'Split'),
    (icon: Icons.timer_outlined, selected: Icons.timer, label: 'Hours'),
    (icon: Icons.person_outline, selected: Icons.person, label: 'Profile'),
  ];

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      // Tapping the active tab pops to its root.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onTap,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selected),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
