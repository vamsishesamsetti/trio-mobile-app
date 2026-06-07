import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/widgets/async_widgets.dart';
import '../../profile/profile_repository.dart';
import '../models.dart';
import '../split_providers.dart';
import 'group_detail_page.dart';

class SplitPage extends ConsumerWidget {
  const SplitPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsProvider);
    final overall = ref.watch(myOverallBalanceProvider);
    final cur = ref.watch(displayCurrencyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Split'),
        actions: [
          TextButton.icon(
            onPressed: () => _joinGroup(context, ref),
            icon: const Icon(Icons.login),
            label: const Text('Join'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createGroup(context, ref),
        icon: const Icon(Icons.group_add),
        label: const Text('Group'),
      ),
      body: AsyncView(
        value: groupsAsync,
        onRetry: () => ref.invalidate(groupsProvider),
        data: (groups) {
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(groupsProvider),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _OverallCard(balance: overall, currency: cur),
                const SizedBox(height: 12),
                if (groups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: EmptyView(
                      icon: Icons.groups_outlined,
                      title: 'No groups yet',
                      subtitle:
                          'Create a group, add people by email, and start splitting expenses.',
                    ),
                  )
                else
                  for (final g in groups) _GroupTile(group: g),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _joinGroup(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Join a group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Invite code',
              hintText: 'Paste the code from your invite'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, controller.text.trim()),
              child: const Text('Join')),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    // Accept either a bare code or a trio://join/<code> link.
    final id = code.contains('/') ? code.split('/').last.trim() : code;
    try {
      await ref.read(groupsProvider.notifier).join(id);
      if (context.mounted) showSnack(context, 'Joined the group!');
    } catch (e) {
      final msg = '$e'.contains('duplicate')
          ? 'You are already in that group.'
          : 'Could not join — check the code. ($e)';
      if (context.mounted) showSnack(context, msg, error: true);
    }
  }

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('New group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Group name', hintText: 'Trip, Apartment, ...'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogCtx, controller.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final cur = ref.read(displayCurrencyProvider);
      final group = await ref.read(groupsProvider.notifier).create(name, cur);
      if (context.mounted) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GroupDetailPage(groupId: group.id)));
      }
    } catch (e) {
      if (context.mounted) showSnack(context, 'Error: $e', error: true);
    }
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.balance, required this.currency});
  final double balance;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final owed = balance >= 0;
    final color = owed ? const Color(0xFF2E9E5B) : const Color(0xFFE0533D);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              balance.abs() < 0.01
                  ? 'You are all settled up'
                  : (owed ? 'You are owed overall' : 'You owe overall'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Text(
              Fmt.money(balance.abs(), currency),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: balance.abs() < 0.01 ? null : color),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupTile extends ConsumerWidget {
  const _GroupTile({required this.group});
  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myBalance = ref.watch(myGroupBalanceProvider(group.id));
    final settled = myBalance.abs() < 0.01;
    final owed = myBalance >= 0;
    final color = owed ? const Color(0xFF2E9E5B) : const Color(0xFFE0533D);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(group.name.isEmpty ? '?' : group.name[0].toUpperCase()),
        ),
        title: Text(group.name),
        subtitle: Text(settled
            ? 'Settled up'
            : (owed ? 'you are owed' : 'you owe')),
        trailing: settled
            ? const Icon(Icons.check_circle, color: Color(0xFF2E9E5B))
            : Text(
                Fmt.money(myBalance.abs(), group.defaultCurrency),
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GroupDetailPage(groupId: group.id))),
      ),
    );
  }
}
