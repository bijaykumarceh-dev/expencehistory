import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expencehistory/main.dart';
import 'package:expencehistory/tracker_models.dart';
import 'package:expencehistory/weekly_report.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'balance combines opening balance, income and expense across wallets',
    () {
      const wallets = [
        Wallet(id: 'cash', name: 'Cash', type: 'Cash', openingBalance: 1200),
        Wallet(id: 'bank', name: 'Bank', type: 'Bank', openingBalance: 500),
      ];
      final transactions = [
        MoneyTransaction(
          id: 'income',
          amount: 800,
          isIncome: true,
          category: 'Salary',
          walletId: 'bank',
          date: DateTime(2026, 11, 12),
          note: '',
        ),
        MoneyTransaction(
          id: 'expense',
          amount: 250,
          isIncome: false,
          category: 'Food',
          walletId: 'cash',
          date: DateTime(2026, 11, 13),
          note: '',
        ),
      ];

      expect(calculateBalance(wallets, transactions), 2250);
    },
  );

  test('week calculations use Monday as the start and report net status', () {
    expect(mondayOf(DateTime(2026, 11, 13)), DateTime(2026, 11, 9));
    expect(weekStatus(10), 'Profit');
    expect(weekStatus(-10), 'Loss');
    expect(weekStatus(0), 'Break-even');
  });

  test('weekly PDF report is generated for the selected week', () async {
    final bytes = await buildWeeklyReportPdf(
      weekStart: DateTime(2026, 11, 9),
      transactions: [
        MoneyTransaction(
          id: 'pdf-income',
          amount: 1200,
          isIncome: true,
          category: 'Salary',
          walletId: 'cash',
          date: DateTime(2026, 11, 10),
          note: 'Pay',
        ),
        MoneyTransaction(
          id: 'pdf-expense',
          amount: 75.5,
          isIncome: false,
          category: 'Food',
          walletId: 'cash',
          date: DateTime(2026, 11, 11),
          note: 'Lunch',
        ),
      ],
      wallets: const [
        Wallet(id: 'cash', name: 'Cash', type: 'Cash', openingBalance: 0),
      ],
      openingBalance: 500,
      closingBalance: 1624.5,
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('transactions persist locally and update the wallet balance', () async {
    final store = await TrackerStore.load();
    await store.saveTransaction(
      MoneyTransaction(
        id: 'test-expense',
        amount: 125,
        isIncome: false,
        category: 'Food',
        walletId: store.wallets.single.id,
        date: DateTime(2026, 11, 13, 14, 30),
        note: 'Lunch',
      ),
    );

    final restored = await TrackerStore.load();
    expect(restored.transactions.single.note, 'Lunch');
    expect(restored.balance, -125);
  });

  testWidgets('shows the tracker home after loading local data', (
    tester,
  ) async {
    await tester.pumpWidget(const ExpenseTrackerApp());
    await tester.pumpAndSettle();

    expect(find.text('KhataFlow'), findsOneWidget);
    expect(find.text('TOTAL BALANCE'), findsOneWidget);
    expect(find.text('Income this week'), findsOneWidget);
    expect(find.text('Weekly spending'), findsOneWidget);
  });

  testWidgets('setting and using a PIN does not crash the app', (tester) async {
    await tester.pumpWidget(const ExpenseTrackerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set app PIN'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.tap(find.text('Save PIN'));
    await tester.pumpAndSettle();

    expect(
      find.text('PIN saved. App lock will appear next time you open the app.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Lock now'));
    await tester.pumpAndSettle();
    expect(find.text('App locked'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
