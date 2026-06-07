import 'models.dart';

/// Pure, dependency-free math for shared expenses. Kept separate from UI and
/// Supabase so it can be unit-tested in isolation (see test/split_engine_test.dart).
///
/// All money is handled in integer **cents** internally to avoid floating point
/// drift, then converted back to dollars. The sum of computed shares always
/// equals the original total exactly.

int _cents(double dollars) => (dollars * 100).round();
double _dollars(int cents) => cents / 100.0;

/// Computes how much each participant owes for one expense.
///
/// - [SplitType.equal]: ignores [weights]; divides evenly, giving leftover
///   cents to the earliest participants.
/// - [SplitType.exact]: [weights] are exact owed dollar amounts per user.
/// - [SplitType.percent]: [weights] are percentages (should sum to 100).
/// - [SplitType.shares]: [weights] are share counts (e.g. 2 vs 1).
///
/// Returns a map of userId -> owed dollars whose values sum to [total].
Map<String, double> computeSplitAmounts({
  required double total,
  required SplitType type,
  required List<String> participants,
  Map<String, double> weights = const {},
}) {
  if (participants.isEmpty) return {};
  final totalCents = _cents(total);

  switch (type) {
    case SplitType.equal:
      return _distributeByWeights(
        totalCents,
        {for (final p in participants) p: 1.0},
        participants,
      );

    case SplitType.exact:
      // Trust provided amounts but reconcile rounding against the total.
      final result = {
        for (final p in participants) p: _cents(weights[p] ?? 0),
      };
      _reconcile(result, totalCents, participants);
      return result.map((k, v) => MapEntry(k, _dollars(v)));

    case SplitType.percent:
      return _distributeByWeights(
        totalCents,
        {for (final p in participants) p: weights[p] ?? 0},
        participants,
      );

    case SplitType.shares:
      return _distributeByWeights(
        totalCents,
        {for (final p in participants) p: weights[p] ?? 0},
        participants,
      );
  }
}

/// Splits [totalCents] proportionally to [weights], assigning any leftover
/// cents (from rounding) one-by-one to the largest fractional remainders.
Map<String, double> _distributeByWeights(
  int totalCents,
  Map<String, double> weights,
  List<String> order,
) {
  final weightSum = weights.values.fold<double>(0, (s, w) => s + w);
  if (weightSum <= 0) {
    // Degenerate: fall back to equal split.
    return _distributeByWeights(
        totalCents, {for (final p in order) p: 1.0}, order);
  }

  final exact = <String, double>{};
  final floor = <String, int>{};
  var assigned = 0;
  for (final p in order) {
    final share = totalCents * (weights[p]! / weightSum);
    exact[p] = share;
    floor[p] = share.floor();
    assigned += floor[p]!;
  }

  var remainder = totalCents - assigned;
  // Give the extra cents to the entries with the biggest fractional part.
  final byFraction = order.toList()
    ..sort((a, b) =>
        (exact[b]! - floor[b]!).compareTo(exact[a]! - floor[a]!));
  for (var i = 0; i < remainder; i++) {
    floor[byFraction[i % byFraction.length]] =
        floor[byFraction[i % byFraction.length]]! + 1;
  }

  return {for (final p in order) p: _dollars(floor[p]!)};
}

/// Pushes any difference between the sum of [parts] and [totalCents] onto the
/// first participant, so exact splits always tie out to the total.
void _reconcile(Map<String, int> parts, int totalCents, List<String> order) {
  final sum = parts.values.fold<int>(0, (s, v) => s + v);
  final diff = totalCents - sum;
  if (diff != 0 && order.isNotEmpty) {
    parts[order.first] = (parts[order.first] ?? 0) + diff;
  }
}

/// Net balance per member across a group: positive = they are owed money,
/// negative = they owe money. The values always sum to ~0.
Map<String, double> netBalances({
  required List<Expense> expenses,
  required List<Settlement> settlements,
  required Iterable<String> memberIds,
}) {
  final net = <String, int>{for (final m in memberIds) m: 0};

  for (final e in expenses) {
    net[e.paidBy] = (net[e.paidBy] ?? 0) + _cents(e.amount);
    for (final s in e.splits) {
      net[s.userId] = (net[s.userId] ?? 0) - _cents(s.owedAmount);
    }
  }
  for (final s in settlements) {
    // from_user pays to_user in cash, reducing from_user's debt.
    net[s.fromUser] = (net[s.fromUser] ?? 0) + _cents(s.amount);
    net[s.toUser] = (net[s.toUser] ?? 0) - _cents(s.amount);
  }

  return net.map((k, v) => MapEntry(k, _dollars(v)));
}

/// A single suggested payment to settle up.
class DebtTransfer {
  final String from;
  final String to;
  final double amount;
  const DebtTransfer(this.from, this.to, this.amount);

  @override
  String toString() => '$from -> $to: ${amount.toStringAsFixed(2)}';
}

/// Greedily minimizes the number of payments needed to zero out [net].
/// Repeatedly matches the biggest debtor with the biggest creditor.
List<DebtTransfer> simplifyDebts(Map<String, double> net) {
  final creditors = <MapEntry<String, int>>[];
  final debtors = <MapEntry<String, int>>[];
  net.forEach((id, bal) {
    final c = _cents(bal);
    if (c > 0) creditors.add(MapEntry(id, c));
    if (c < 0) debtors.add(MapEntry(id, -c)); // store positive magnitude
  });

  creditors.sort((a, b) => b.value.compareTo(a.value));
  debtors.sort((a, b) => b.value.compareTo(a.value));

  final transfers = <DebtTransfer>[];
  var i = 0, j = 0;
  final cred = creditors.map((e) => [e.key, e.value]).toList();
  final debt = debtors.map((e) => [e.key, e.value]).toList();

  while (i < debt.length && j < cred.length) {
    final owe = debt[i][1] as int;
    final due = cred[j][1] as int;
    final pay = owe < due ? owe : due;
    if (pay > 0) {
      transfers.add(DebtTransfer(
          debt[i][0] as String, cred[j][0] as String, _dollars(pay)));
    }
    debt[i][1] = owe - pay;
    cred[j][1] = due - pay;
    if (debt[i][1] == 0) i++;
    if (cred[j][1] == 0) j++;
  }
  return transfers;
}
