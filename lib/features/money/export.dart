import 'dart:io' show File;

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/formatters.dart';
import '../../core/widgets/async_widgets.dart';
import 'models.dart';
import 'money_providers.dart';

/// Builds a CSV of all transactions and shares it via the OS share sheet.
Future<void> exportTransactionsCsv(BuildContext context, WidgetRef ref) async {
  final txns = ref.read(transactionsProvider).value ?? const [];
  if (txns.isEmpty) {
    showSnack(context, 'Nothing to export yet');
    return;
  }
  final cats = ref.read(categoryByIdProvider);
  final accts = ref.read(accountByIdProvider);

  final rows = <List<dynamic>>[
    ['Date', 'Type', 'Amount', 'Currency', 'Category', 'Account', 'To', 'Note'],
    for (final t in txns)
      [
        Fmt.dateMedium(t.date),
        t.type.name,
        t.amount.toStringAsFixed(2),
        t.currency,
        t.type == TxnType.transfer ? '' : (cats[t.categoryId]?.name ?? ''),
        accts[t.accountId]?.name ?? '',
        accts[t.transferAccountId]?.name ?? '',
        t.note ?? '',
      ],
  ];
  final csv = const CsvEncoder().convert(rows);

  try {
    if (kIsWeb) {
      await SharePlus.instance.share(ShareParams(
        text: csv,
        subject: 'Trio transactions',
      ));
    } else {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/trio_transactions_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: 'Trio transactions',
      ));
    }
  } catch (e) {
    if (context.mounted) showSnack(context, 'Export failed: $e', error: true);
  }
}
