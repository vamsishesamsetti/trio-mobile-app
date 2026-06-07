import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/prefs.dart';
import '../../core/supabase.dart';
import '../../core/widgets/async_widgets.dart';
import '../auth/auth_repository.dart';
import 'profile_model.dart';
import 'profile_repository.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  static const currencies = [
    'USD', 'EUR', 'GBP', 'INR', 'JPY', 'CAD', 'AUD', 'CHF', 'CNY', 'AED',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeModeProvider);
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: AsyncView(
        value: profileAsync,
        onRetry: () => ref.invalidate(myProfileProvider),
        data: (profile) {
          final name = profile?.displayName ??
              user?.email?.split('@').first ??
              'You';
          final email = profile?.email ?? user?.email ?? '';
          return ListView(
            children: [
              const SizedBox(height: 16),
              Center(child: _Avatar(profile: profile, fallback: name)),
              const SizedBox(height: 12),
              Center(
                  child: Text(name,
                      style: Theme.of(context).textTheme.titleLarge)),
              Center(
                  child: Text(email,
                      style: Theme.of(context).textTheme.bodySmall)),
              const SizedBox(height: 16),

              _sectionLabel(context, 'Account'),
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Display name'),
                subtitle: Text(name),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editName(context, ref, profile?.displayName ?? ''),
              ),
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Default currency'),
                trailing: DropdownButton<String>(
                  value: currencies.contains(profile?.defaultCurrency)
                      ? profile!.defaultCurrency
                      : 'USD',
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final c in currencies)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(myProfileProvider.notifier)
                          .save(defaultCurrency: v);
                    }
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Change password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _changePassword(context, ref),
              ),

              const Divider(),
              _sectionLabel(context, 'Appearance'),
              RadioGroup<ThemeMode>(
                groupValue: themeMode,
                onChanged: (m) {
                  if (m != null) ref.read(themeModeProvider.notifier).set(m);
                },
                child: const Column(
                  children: [
                    RadioListTile(
                        value: ThemeMode.system,
                        title: Text('System default')),
                    RadioListTile(value: ThemeMode.light, title: Text('Light')),
                    RadioListTile(value: ThemeMode.dark, title: Text('Dark')),
                  ],
                ),
              ),

              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Sign out',
                    style: TextStyle(color: Colors.red)),
                onTap: () => ref.read(authRepositoryProvider).signOut(),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  Future<void> _editName(
      BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await ref.read(myProfileProvider.notifier).save(displayName: name);
      if (context.mounted) showSnack(context, 'Name updated');
    } catch (e) {
      if (context.mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final pw = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Change password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pw,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Confirm password'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Update')),
        ],
      ),
    );
    if (ok != true) return;
    if (pw.text.length < 6) {
      if (context.mounted) {
        showSnack(context, 'Password must be at least 6 characters',
            error: true);
      }
      return;
    }
    if (pw.text != confirm.text) {
      if (context.mounted) showSnack(context, 'Passwords do not match', error: true);
      return;
    }
    try {
      await ref.read(myProfileProvider.notifier).changePassword(pw.text);
      if (context.mounted) showSnack(context, 'Password updated');
    } catch (e) {
      if (context.mounted) showSnack(context, 'Error: $e', error: true);
    }
  }
}

class _Avatar extends ConsumerWidget {
  const _Avatar({required this.profile, required this.fallback});
  final Profile? profile;
  final String fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = profile?.avatarUrl;
    return Stack(
      children: [
        CircleAvatar(
          radius: 44,
          backgroundImage: (url != null && url.isNotEmpty)
              ? NetworkImage(url)
              : null,
          child: (url == null || url.isEmpty)
              ? Text(fallback.isEmpty ? '?' : fallback[0].toUpperCase(),
                  style: const TextStyle(fontSize: 32))
              : null,
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Material(
            color: Theme.of(context).colorScheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _pickAvatar(context, ref),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.camera_alt, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickAvatar(BuildContext context, WidgetRef ref) async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 60);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    try {
      await ref.read(myProfileProvider.notifier).setAvatar(bytes);
      if (context.mounted) showSnack(context, 'Photo updated');
    } catch (e) {
      if (context.mounted) showSnack(context, 'Error: $e', error: true);
    }
  }
}
