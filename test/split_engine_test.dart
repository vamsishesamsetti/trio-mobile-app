import 'package:flutter_test/flutter_test.dart';
import 'package:trio/features/split/models.dart';
import 'package:trio/features/split/split_engine.dart';

double sum(Map<String, double> m) =>
    m.values.fold<double>(0, (s, v) => s + v);

Expense _exp({
  required String paidBy,
  required double amount,
  required Map<String, double> owed,
}) {
  return Expense(
    id: 'e',
    groupId: 'g',
    paidBy: paidBy,
    description: 'x',
    amount: amount,
    currency: 'USD',
    date: DateTime(2026),
    splitType: SplitType.equal,
    category: null,
    createdAt: DateTime(2026),
    splits: [
      for (final entry in owed.entries)
        ExpenseSplit(
            id: 'sp_${entry.key}',
            expenseId: 'e',
            userId: entry.key,
            owedAmount: entry.value),
    ],
  );
}

void main() {
  group('computeSplitAmounts', () {
    test('equal split divides evenly', () {
      final r = computeSplitAmounts(
        total: 90,
        type: SplitType.equal,
        participants: ['a', 'b', 'c'],
      );
      expect(r['a'], 30);
      expect(r['b'], 30);
      expect(r['c'], 30);
      expect(sum(r), closeTo(90, 0.0001));
    });

    test('equal split distributes leftover cents and ties to total', () {
      final r = computeSplitAmounts(
        total: 100,
        type: SplitType.equal,
        participants: ['a', 'b', 'c'],
      );
      // 100 / 3 = 33.33, 33.33, 33.34
      expect(sum(r), closeTo(100, 0.0001));
      expect(r.values.every((v) => (v - 33.33).abs() < 0.02), isTrue);
    });

    test('exact split keeps amounts and reconciles rounding', () {
      final r = computeSplitAmounts(
        total: 100,
        type: SplitType.exact,
        participants: ['a', 'b'],
        weights: {'a': 70, 'b': 30},
      );
      expect(r['a'], 70);
      expect(r['b'], 30);
      expect(sum(r), closeTo(100, 0.0001));
    });

    test('percent split', () {
      final r = computeSplitAmounts(
        total: 200,
        type: SplitType.percent,
        participants: ['a', 'b'],
        weights: {'a': 25, 'b': 75},
      );
      expect(r['a'], 50);
      expect(r['b'], 150);
      expect(sum(r), closeTo(200, 0.0001));
    });

    test('shares split (2:1)', () {
      final r = computeSplitAmounts(
        total: 90,
        type: SplitType.shares,
        participants: ['a', 'b'],
        weights: {'a': 2, 'b': 1},
      );
      expect(r['a'], 60);
      expect(r['b'], 30);
      expect(sum(r), closeTo(90, 0.0001));
    });

    test('always sums to total even with awkward division', () {
      final r = computeSplitAmounts(
        total: 10,
        type: SplitType.equal,
        participants: ['a', 'b', 'c', 'd', 'e', 'f', 'g'],
      );
      expect(sum(r), closeTo(10, 0.0001));
    });
  });

  group('netBalances', () {
    test('single expense paid by one, split equally', () {
      // a pays 90, split 3 ways -> a is owed 60, b and c owe 30 each.
      final exp = _exp(
        paidBy: 'a',
        amount: 90,
        owed: {'a': 30, 'b': 30, 'c': 30},
      );
      final net = netBalances(
        expenses: [exp],
        settlements: const [],
        memberIds: ['a', 'b', 'c'],
      );
      expect(net['a'], closeTo(60, 0.0001));
      expect(net['b'], closeTo(-30, 0.0001));
      expect(net['c'], closeTo(-30, 0.0001));
      expect(sum(net), closeTo(0, 0.0001));
    });

    test('settlement reduces debt', () {
      final exp = _exp(paidBy: 'a', amount: 100, owed: {'a': 50, 'b': 50});
      // b owes a 50, then b pays a 50 -> all square.
      final net = netBalances(
        expenses: [exp],
        settlements: [
          Settlement(
              id: 's',
              groupId: 'g',
              fromUser: 'b',
              toUser: 'a',
              amount: 50,
              settledAt: DateTime(2026)),
        ],
        memberIds: ['a', 'b'],
      );
      expect(net['a'], closeTo(0, 0.0001));
      expect(net['b'], closeTo(0, 0.0001));
    });
  });

  group('simplifyDebts', () {
    test('two-party debt produces one transfer', () {
      final transfers = simplifyDebts({'a': 30.0, 'b': -30.0});
      expect(transfers.length, 1);
      expect(transfers.first.from, 'b');
      expect(transfers.first.to, 'a');
      expect(transfers.first.amount, closeTo(30, 0.0001));
    });

    test('minimizes transfers in a 3-way cycle', () {
      // a is owed 20, b is owed 10, c owes 30.
      final transfers = simplifyDebts({'a': 20.0, 'b': 10.0, 'c': -30.0});
      // c can pay both with 2 transfers; no more than 2 needed.
      expect(transfers.length, lessThanOrEqualTo(2));
      final total = transfers.fold<double>(0, (s, t) => s + t.amount);
      expect(total, closeTo(30, 0.0001));
      expect(transfers.every((t) => t.from == 'c'), isTrue);
    });

    test('balanced group yields no transfers', () {
      final transfers = simplifyDebts({'a': 0.0, 'b': 0.0});
      expect(transfers, isEmpty);
    });
  });
}
