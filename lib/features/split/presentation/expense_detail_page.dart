import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../../../core/supabase.dart';
import '../../../core/widgets/async_widgets.dart';
import '../models.dart';
import '../split_providers.dart';
import 'add_expense_page.dart';

/// Full breakdown of one shared expense: who paid, the split mode, and exactly
/// what each person owes.
class ExpenseDetailPage extends ConsumerWidget {
  const ExpenseDetailPage({
    super.key,
    required this.groupId,
    required this.expense,
    required this.labels,
  });

  final String groupId;
  final Expense expense;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(supabaseProvider).auth.currentUser?.id;
    final scheme = Theme.of(context).colorScheme;
    final splits = [...expense.splits]
      ..sort((a, b) => b.owedAmount.compareTo(a.owedAmount));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense'),
        actions: [
          if (!expense.isDeleted) ...[
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AddExpensePage(
                        groupId: groupId, existing: expense)));
              },
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (expense.isDeleted)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.delete_outline, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Deleted by ${labels[expense.deletedBy] ?? 'someone'} on ${Fmt.dateTime(expense.deletedAt!)}',
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ]),
            ),
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                      kSplitCategories[expense.category] ?? Icons.receipt_long,
                      size: 30),
                ),
                const SizedBox(height: 12),
                Text(expense.description,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(Fmt.money(expense.amount, expense.currency),
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _InfoRow(
              icon: Icons.account_circle_outlined,
              label: 'Paid by',
              value: labels[expense.paidBy] ?? 'Someone'),
          _InfoRow(
              icon: Icons.event,
              label: 'Date',
              value: Fmt.dateFull(expense.date)),
          _InfoRow(
              icon: Icons.category_outlined,
              label: 'Category',
              value: expense.category ?? 'General'),
          _InfoRow(
              icon: Icons.call_split,
              label: 'Split',
              value: _splitLabel(expense.splitType)),
          if (expense.receiptUrl != null) ...[
            const SizedBox(height: 16),
            Text('Receipt', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (_) => Dialog(
                  child: InteractiveViewer(
                    child: Image.network(expense.receiptUrl!),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  expense.receiptUrl!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 100,
                    color: scheme.surfaceContainerHighest,
                    child: const Center(child: Text('Receipt unavailable')),
                  ),
                ),
              ),
            ),
          ],
          const Divider(height: 32),
          Text('Breakdown', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final s in splits)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                  child: Text((labels[s.userId] ?? '?')[0].toUpperCase())),
              title: Text(
                  '${labels[s.userId] ?? 'Member'}${s.userId == uid ? ' (you)' : ''}'),
              subtitle: s.userId == expense.paidBy
                  ? const Text('paid the bill')
                  : null,
              trailing: Text(Fmt.money(s.owedAmount, expense.currency),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          const Divider(height: 32),
          _CommentsSection(expenseId: expense.id, uid: uid),
        ],
      ),
    );
  }

  String _splitLabel(SplitType t) => switch (t) {
        SplitType.equal => 'Split equally',
        SplitType.exact => 'Exact amounts',
        SplitType.percent => 'By percentage',
        SplitType.shares => 'By shares',
      };

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('"${expense.description}" will be removed for everyone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(splitActionsProvider)
          .deleteExpense(groupId, expense.id);
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) showSnack(context, 'Error: $e', error: true);
    }
  }
}

/// Comment thread for an expense — everyone in the group can read & post.
class _CommentsSection extends ConsumerStatefulWidget {
  const _CommentsSection({required this.expenseId, required this.uid});
  final String expenseId;
  final String? uid;

  @override
  ConsumerState<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<_CommentsSection> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(splitActionsProvider).addComment(widget.expenseId, body);
      _controller.clear();
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(expenseCommentsProvider(widget.expenseId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Comments', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Could not load comments: $e',
              style: Theme.of(context).textTheme.bodySmall),
          data: (comments) {
            if (comments.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No comments yet. Start the conversation.',
                    style: Theme.of(context).textTheme.bodySmall),
              );
            }
            return Column(
              children: [
                for (final c in comments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                        radius: 16,
                        child: Text(
                            (c.displayName ?? '?')[0].toUpperCase(),
                            style: const TextStyle(fontSize: 13))),
                    title: Text(c.displayName ?? 'Member',
                        style: Theme.of(context).textTheme.labelLarge),
                    subtitle: Text(c.body),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(Fmt.dateTime(c.createdAt),
                            style: Theme.of(context).textTheme.bodySmall),
                        if (c.userId == widget.uid)
                          InkWell(
                            onTap: () => ref
                                .read(splitActionsProvider)
                                .deleteComment(widget.expenseId, c.id),
                            child: const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(Icons.delete_outline, size: 16),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                    hintText: 'Add a comment', isDense: true),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 12),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
