import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tracker_models.dart';

const _ink = Color(0xFF15251F);
const _green = Color(0xFF16845B);
const _surface = Color(0xFFF5F7F5);

void main() {
  runApp(const ExpenseTrackerApp());
}

class TrackerStore extends ChangeNotifier {
  TrackerStore._(this._preferences);

  static const _storageKey = 'expense_tracker_snapshot_v1';
  final SharedPreferences _preferences;
  List<Wallet> wallets = [];
  List<MoneyTransaction> transactions = [];
  List<String> categories = [
    'Food',
    'Travel',
    'Bills',
    'Shopping',
    'Salary',
    'Business',
    'Other',
  ];
  String? _pinSalt;
  String? _pinHash;

  bool get hasPin => _pinHash != null;
  double get balance => calculateBalance(wallets, transactions);

  static Future<TrackerStore> load() async {
    final preferences = await SharedPreferences.getInstance();
    final store = TrackerStore._(preferences);
    final saved = preferences.getString(_storageKey);
    if (saved != null) {
      final snapshot = jsonDecode(saved) as Map<String, dynamic>;
      store.wallets = walletsFromSnapshot(snapshot);
      store.transactions = transactionsFromSnapshot(snapshot);
      store.categories = (snapshot['categories'] as List<dynamic>? ?? [])
          .cast<String>();
      store._pinSalt = snapshot['pinSalt'] as String?;
      store._pinHash = snapshot['pinHash'] as String?;
    }
    if (store.wallets.isEmpty) {
      store.wallets = [
        Wallet(
          id: 'cash-default',
          name: 'Cash',
          type: 'Cash',
          openingBalance: 0,
        ),
      ];
      await store._save();
    }
    if (store.categories.isEmpty) {
      store.categories = [
        'Food',
        'Travel',
        'Bills',
        'Shopping',
        'Salary',
        'Other',
      ];
      await store._save();
    }
    return store;
  }

  Future<void> _save() async {
    final snapshot = encodeSnapshot(
      wallets: wallets,
      transactions: transactions,
      categories: categories,
      pinSalt: _pinSalt,
      pinHash: _pinHash,
    );
    final saved = await _preferences.setString(
      _storageKey,
      snapshotToJson(snapshot),
    );
    if (!saved) throw StateError('Could not save your data on this device.');
  }

  Future<void> saveTransaction(MoneyTransaction transaction) async {
    final index = transactions.indexWhere((item) => item.id == transaction.id);
    if (index < 0) {
      transactions = [transaction, ...transactions];
    } else {
      transactions = [...transactions]..[index] = transaction;
    }
    await _save();
    notifyListeners();
  }

  Future<void> deleteTransaction(String id) async {
    transactions = transactions.where((item) => item.id != id).toList();
    await _save();
    notifyListeners();
  }

  Future<void> addWallet(Wallet wallet) async {
    wallets = [...wallets, wallet];
    await _save();
    notifyListeners();
  }

  Future<void> addCategory(String category) async {
    if (categories.any(
      (value) => value.toLowerCase() == category.toLowerCase(),
    )) {
      throw StateError('That category already exists.');
    }
    categories = [...categories, category];
    await _save();
    notifyListeners();
  }

  Future<void> setPin(String pin) async {
    _pinSalt = DateTime.now().microsecondsSinceEpoch.toString();
    _pinHash = _hashPin(pin, _pinSalt!);
    await _save();
    notifyListeners();
  }

  bool verifyPin(String pin) =>
      _pinSalt != null && _pinHash == _hashPin(pin, _pinSalt!);

  String _hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
}

class ExpenseTrackerApp extends StatefulWidget {
  const ExpenseTrackerApp({super.key});

  @override
  State<ExpenseTrackerApp> createState() => _ExpenseTrackerAppState();
}

class _ExpenseTrackerAppState extends State<ExpenseTrackerApp> {
  late final Future<TrackerStore> _store = TrackerStore.load();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'KhataFlow',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _green),
      scaffoldBackgroundColor: _surface,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: _surface,
        foregroundColor: _ink,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: FutureBuilder<TrackerStore>(
      future: _store,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StartupError(error: snapshot.error!);
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return TrackerHome(store: snapshot.data!);
      },
    ),
  );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Could not open your saved data.\n$error'),
      ),
    ),
  );
}

class TrackerHome extends StatefulWidget {
  const TrackerHome({required this.store, super.key});
  final TrackerStore store;

  @override
  State<TrackerHome> createState() => _TrackerHomeState();
}

class _TrackerHomeState extends State<TrackerHome> with WidgetsBindingObserver {
  int _tab = 0;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _locked = widget.store.hasPin;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && widget.store.hasPin && mounted) {
      setState(() => _locked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(
        store: widget.store,
        onAdd: () => _openTransaction(),
        onSeeAll: () => setState(() => _tab = 1),
      ),
      TransactionsScreen(store: widget.store, onAdd: _openTransaction),
      WeeksScreen(store: widget.store),
      SettingsScreen(
        store: widget.store,
        onLock: () => setState(() => _locked = true),
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            IndexedStack(index: _tab, children: pages),
            if (_locked)
              Positioned.fill(
                child: PinLockScreen(
                  store: widget.store,
                  onUnlocked: () => setState(() => _locked = false),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: !_locked && _tab < 2
          ? FloatingActionButton(
              onPressed: _openTransaction,
              backgroundColor: _green,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Entries',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Future<void> _openTransaction([MoneyTransaction? transaction]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _surface,
      builder: (context) =>
          TransactionForm(store: widget.store, transaction: transaction),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    required this.store,
    required this.onAdd,
    required this.onSeeAll,
    super.key,
  });
  final TrackerStore store;
  final VoidCallback onAdd;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final now = DateTime.now();
        final weekStart = mondayOf(now);
        final weekItems = store.transactions
            .where((item) => !item.date.isBefore(weekStart))
            .toList();
        final income = _sum(weekItems, true);
        final expense = _sum(weekItems, false);
        final recent = [...store.transactions]
          ..sort((a, b) => b.date.compareTo(a.date));
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'KhataFlow',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                            Text('Your money, in balance'),
                          ],
                        ),
                      ),
                      CircleAvatar(
                        backgroundColor: const Color(0xFFDCEFE6),
                        foregroundColor: _green,
                        child: Text(
                          DateTime.now().day.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _BalanceCard(
                    balance: store.balance,
                    walletCount: store.wallets.length,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          title: 'Income this week',
                          amount: income,
                          icon: Icons.south_west,
                          tint: _green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: 'Spent this week',
                          amount: expense,
                          icon: Icons.north_east,
                          tint: const Color(0xFFD65A53),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _WeekChart(
                    transactions: store.transactions,
                    weekStart: weekStart,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Recent transactions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: onSeeAll,
                        child: const Text('See all'),
                      ),
                    ],
                  ),
                  if (recent.isEmpty)
                    const _EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No entries yet',
                      message:
                          'Add your first income or expense to get started.',
                    )
                  else
                    ...recent
                        .take(5)
                        .map(
                          (item) => _TransactionTile(
                            transaction: item,
                            wallet: _walletName(store.wallets, item.walletId),
                            onTap: () =>
                                _showTransactionDetail(context, store, item),
                          ),
                        ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: const Text('Add transaction'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.walletCount});
  final double balance;
  final int walletCount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF116C4A), Color(0xFF209C6C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('TOTAL BALANCE', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 8),
        Text(
          _money(balance),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              size: 18,
              color: Colors.white70,
            ),
            const SizedBox(width: 8),
            Text(
              '$walletCount ${walletCount == 1 ? 'wallet' : 'wallets'}',
              style: const TextStyle(color: Colors.white),
            ),
            const Spacer(),
            const Text(
              'Opening balance + income − expense',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.amount,
    required this.icon,
    required this.tint,
  });
  final String title;
  final double amount;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: tint),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _money(amount),
            style: const TextStyle(
              color: _ink,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.transactions, required this.weekStart});
  final List<MoneyTransaction> transactions;
  final DateTime weekStart;

  @override
  Widget build(BuildContext context) {
    final values = List<double>.filled(7, 0);
    for (final item in transactions) {
      final day = DateTime(item.date.year, item.date.month, item.date.day);
      final index = day.difference(weekStart).inDays;
      if (index >= 0 && index < 7 && !item.isIncome) {
        values[index] += item.amount;
      }
    }
    final maxValue = values.fold<double>(
      0,
      (max, value) => value > max ? value : max,
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Weekly spending',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 3),
          Text(
            '${_formatDate(weekStart)} – ${_formatDate(weekStart.add(const Duration(days: 6)))}',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (index) {
                final ratio = maxValue == 0 ? 0.06 : values[index] / maxValue;
                final date = weekStart.add(Duration(days: index));
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        height: 62 * ratio.clamp(0.06, 1),
                        width: 18,
                        decoration: BoxDecoration(
                          color: const Color(0xFF79C6A0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: date.day == DateTime.now().day
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    required this.store,
    required this.onAdd,
    super.key,
  });
  final TrackerStore store;
  final ValueChanged<MoneyTransaction?> onAdd;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final items = [...widget.store.transactions]
        ..sort((a, b) => b.date.compareTo(a.date));
      final visible = items.where((item) {
        if (_filter == 'Income') return item.isIncome;
        if (_filter == 'Expense') return !item.isIncome;
        return true;
      }).toList();
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const Text(
                  'Transactions',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text('${items.length} entries recorded'),
                const SizedBox(height: 18),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'All', label: Text('All')),
                    ButtonSegment(value: 'Income', label: Text('Income')),
                    ButtonSegment(value: 'Expense', label: Text('Expense')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (value) =>
                      setState(() => _filter = value.first),
                ),
                const SizedBox(height: 14),
                if (visible.isEmpty)
                  const _EmptyState(
                    icon: Icons.search_off,
                    title: 'Nothing to show',
                    message: 'Your transactions will appear here.',
                  )
                else
                  ...visible.map(
                    (item) => _TransactionTile(
                      transaction: item,
                      wallet: _walletName(widget.store.wallets, item.walletId),
                      onTap: () =>
                          _showTransactionDetail(context, widget.store, item),
                    ),
                  ),
              ]),
            ),
          ),
        ],
      );
    },
  );
}

class WeeksScreen extends StatelessWidget {
  const WeeksScreen({required this.store, super.key});
  final TrackerStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final weeks = _weekStarts(store.transactions);
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const Text(
                  'Weekly history',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text('Monday to Sunday · weekly closing balance'),
                const SizedBox(height: 18),
                if (weeks.isEmpty)
                  const _EmptyState(
                    icon: Icons.calendar_month_outlined,
                    title: 'Your weekly story starts here',
                    message:
                        'Add a transaction to see weekly income and spending.',
                  )
                else
                  ...weeks.map(
                    (start) => _WeekCard(
                      store: store,
                      start: start,
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (context) =>
                            WeekDetailSheet(store: store, start: start),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ],
      );
    },
  );
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.store,
    required this.start,
    required this.onTap,
  });
  final TrackerStore store;
  final DateTime start;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final end = start.add(const Duration(days: 7));
    final items = store.transactions.where(
      (item) => !item.date.isBefore(start) && item.date.isBefore(end),
    );
    final income = _sum(items, true);
    final expense = _sum(items, false);
    final net = income - expense;
    final closing = _balanceAt(
      store,
      end.subtract(const Duration(microseconds: 1)),
    );
    final color = net > 0
        ? _green
        : net < 0
        ? const Color(0xFFD65A53)
        : Colors.blueGrey;
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_formatDate(start)} – ${_formatDate(end.subtract(const Duration(days: 1)))}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      weekStatus(net),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _smallAmount('Income', income, _green),
                  _smallAmount('Expense', expense, const Color(0xFFD65A53)),
                  _smallAmount('Net', net, color),
                ],
              ),
              const Divider(height: 22),
              Row(
                children: [
                  const Text(
                    'Closing balance',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const Spacer(),
                  Text(
                    _money(closing),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallAmount(String label, double amount, Color color) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _money(amount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

class WeekDetailSheet extends StatelessWidget {
  const WeekDetailSheet({required this.store, required this.start, super.key});
  final TrackerStore store;
  final DateTime start;

  @override
  Widget build(BuildContext context) {
    final end = start.add(const Duration(days: 7));
    final items =
        store.transactions
            .where(
              (item) => !item.date.isBefore(start) && item.date.isBefore(end),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final income = _sum(items, true);
    final expense = _sum(items, false);
    final categories = <String, double>{};
    for (final item in items.where((entry) => !entry.isIncome)) {
      categories.update(
        item.category,
        (value) => value + item.amount,
        ifAbsent: () => item.amount,
      );
    }
    final largestCategory = categories.values.fold<double>(
      0,
      (largest, amount) => amount > largest ? amount : largest,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_formatDate(start)} – ${_formatDate(end.subtract(const Duration(days: 1)))}',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _smallAmount('Income', income, _green),
                  _smallAmount('Expense', expense, const Color(0xFFD65A53)),
                  _smallAmount('Net', income - expense, _ink),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Expense by category',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (categories.isEmpty)
                const Text('No expenses this week.')
              else
                ...categories.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(entry.key)),
                            Text(
                              _money(entry.value),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        LinearProgressIndicator(
                          value: entry.value / largestCategory,
                          minHeight: 7,
                          borderRadius: BorderRadius.circular(8),
                          color: _green,
                          backgroundColor: const Color(0xFFE7EEE9),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                'Transactions',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              ...items.map(
                (item) => _TransactionTile(
                  transaction: item,
                  wallet: _walletName(store.wallets, item.walletId),
                  onTap: () => _showTransactionDetail(context, store, item),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.store, required this.onLock, super.key});
  final TrackerStore store;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [
        const Text(
          'Settings',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text('Manage wallets, categories and app security.'),
        const SizedBox(height: 20),
        _SettingsCard(
          title: 'Wallets',
          subtitle:
              '${store.wallets.length} accounts · balance ${_money(store.balance)}',
          icon: Icons.account_balance_wallet_outlined,
          onTap: () => _showWallets(context, store),
        ),
        _SettingsCard(
          title: 'Categories',
          subtitle: '${store.categories.length} categories',
          icon: Icons.category_outlined,
          onTap: () => _showCategories(context, store),
        ),
        _SettingsCard(
          title: store.hasPin ? 'Change app PIN' : 'Set app PIN',
          subtitle: store.hasPin
              ? 'App lock is enabled on this device'
              : 'Protect the app when it is opened',
          icon: Icons.lock_outline,
          onTap: () => _setPin(context, store),
        ),
        if (store.hasPin)
          _SettingsCard(
            title: 'Lock now',
            subtitle: 'Require your PIN to continue',
            icon: Icons.phonelink_lock,
            onTap: onLock,
          ),
        const SizedBox(height: 14),
        const Card(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Offline mode is active. Your information is saved on this device. '
              'Cloud sync and account sign-in need Firebase project setup.',
              style: TextStyle(height: 1.4),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFE6F2EB),
        foregroundColor: _green,
        child: Icon(icon),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class TransactionForm extends StatefulWidget {
  const TransactionForm({required this.store, this.transaction, super.key});
  final TrackerStore store;
  final MoneyTransaction? transaction;

  @override
  State<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<TransactionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late bool _isIncome;
  late String _category;
  late String _walletId;
  late DateTime _date;
  String? _imageBase64;
  String? _qrData;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.transaction;
    _amount = TextEditingController(
      text: item == null ? '' : _number(item.amount),
    );
    _note = TextEditingController(text: item?.note ?? '');
    _isIncome = item?.isIncome ?? false;
    _category = item?.category ?? widget.store.categories.first;
    _walletId = item?.walletId ?? widget.store.wallets.first.id;
    _date = item?.date ?? DateTime.now();
    _imageBase64 = item?.imageBase64;
    _qrData = item?.qrData;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      10,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.transaction == null
                  ? 'Add transaction'
                  : 'Edit transaction',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Expense'),
                  icon: Icon(Icons.north_east),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Income'),
                  icon: Icon(Icons.south_west),
                ),
              ],
              selected: {_isIncome},
              onSelectionChanged: (value) => setState(() {
                _isIncome = value.first;
                if (_isIncome && !widget.store.categories.contains(_category)) {
                  _category = widget.store.categories.first;
                }
              }),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                prefixIcon: Icon(Icons.currency_rupee),
              ),
              validator: (value) {
                final amount = double.tryParse(value?.trim() ?? '');
                if (amount == null || !amount.isFinite || amount <= 0) {
                  return 'Enter an amount greater than zero';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: widget.store.categories
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _category = value!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _walletId,
              decoration: const InputDecoration(labelText: 'Wallet'),
              items: widget.store.wallets
                  .map(
                    (wallet) => DropdownMenuItem(
                      value: wallet.id,
                      child: Text('${wallet.name} · ${wallet.type}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _walletId = value!),
            ),
            const SizedBox(height: 12),
            ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Date'),
              trailing: Text(_formatDateTime(_date)),
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('Time'),
              trailing: Text(_formatTime(_date)),
              onTap: _pickTime,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                prefixIcon: Icon(Icons.notes),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickReceipt,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      _imageBase64 == null ? 'Add receipt' : 'Receipt added',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _scanQr,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR'),
                  ),
                ),
              ],
            ),
            if (_qrData != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'QR details: ${_qrData!.length > 60 ? '${_qrData!.substring(0, 60)}…' : _qrData}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: Text(_saving ? 'Saving…' : 'Save transaction'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(
        () => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (picked != null) {
      setState(
        () => _date = DateTime(
          _date.year,
          _date.month,
          _date.day,
          picked.hour,
          picked.minute,
        ),
      );
    }
  }

  Future<void> _pickReceipt() async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null || !mounted) return;
      final photo = await ImagePicker().pickImage(
        source: source,
        imageQuality: 60,
        maxWidth: 1200,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      if (bytes.length > 1024 * 1024) {
        _showMessage('Image is over 1 MB. Choose a smaller receipt image.');
        return;
      }
      setState(() => _imageBase64 = base64Encode(bytes));
    } catch (error) {
      _showMessage('Could not attach the image: $error');
    }
  }

  Future<void> _scanQr() async {
    final result = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScannerScreen()));
    if (result == null || !mounted) return;
    setState(() {
      _qrData = result;
      final details = _parseUpiQr(result);
      if (details.amount != null && _amount.text.trim().isEmpty) {
        _amount.text = _number(details.amount!);
      }
      if (details.receiver != null && _note.text.trim().isEmpty) {
        _note.text = 'Payment to ${details.receiver}';
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final current = widget.transaction;
    final transaction = MoneyTransaction(
      id: current?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      amount: double.parse(_amount.text.trim()),
      isIncome: _isIncome,
      category: _category,
      walletId: _walletId,
      date: _date,
      note: _note.text.trim(),
      imageBase64: _imageBase64,
      qrData: _qrData,
    );
    try {
      await widget.store.saveTransaction(transaction);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _showMessage('Could not save transaction: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan payment QR')),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          onDetect: (capture) {
            if (_handled) return;
            final value = capture.barcodes.isEmpty
                ? null
                : capture.barcodes.first.rawValue;
            if (value == null || value.isEmpty) return;
            _handled = true;
            Navigator.of(context).pop(value);
          },
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Point the camera at a UPI QR code. Check details before saving.',
              style: TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    ),
  );
}

class _QrDetails {
  const _QrDetails({this.amount, this.receiver});
  final double? amount;
  final String? receiver;
}

_QrDetails _parseUpiQr(String data) {
  final uri = Uri.tryParse(data);
  if (uri == null) return const _QrDetails();
  final amount = double.tryParse(uri.queryParameters['am'] ?? '');
  final receiver =
      uri.queryParameters['pn'] ??
      uri.queryParameters['name'] ??
      uri.queryParameters['payee'];
  return _QrDetails(amount: amount, receiver: receiver);
}

class PinLockScreen extends StatefulWidget {
  const PinLockScreen({
    required this.store,
    required this.onUnlocked,
    super.key,
  });
  final TrackerStore store;
  final VoidCallback onUnlocked;

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  final _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 34,
                backgroundColor: Color(0xFFDCEFE6),
                child: Icon(Icons.lock_outline, color: _green, size: 32),
              ),
              const SizedBox(height: 18),
              const Text(
                'App locked',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text('Enter your PIN to view your tracker.'),
              const SizedBox(height: 20),
              TextField(
                controller: _pin,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: '4–6 digit PIN',
                  errorText: _error,
                  counterText: '',
                ),
                onSubmitted: (_) => _unlock(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _unlock,
                  child: const Text('Unlock'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  void _unlock() {
    if (widget.store.verifyPin(_pin.text)) {
      FocusManager.instance.primaryFocus?.unfocus();
      widget.onUnlocked();
    } else {
      setState(() {
        _error = 'Incorrect PIN';
        _pin.clear();
      });
    }
  }
}

Future<void> _setPin(BuildContext context, TrackerStore store) async {
  final pin = await _showPinEntryDialog(
    context,
    title: store.hasPin ? 'Change app PIN' : 'Set app PIN',
    label: 'Choose a 4–6 digit PIN',
    action: 'Continue',
  );
  if (pin == null || !context.mounted) return;
  final confirmed = await _showPinEntryDialog(
    context,
    title: 'Confirm PIN',
    label: 'Enter the PIN again',
    action: 'Save PIN',
  );
  if (!context.mounted) return;
  if (confirmed != pin) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PINs did not match. No changes were made.'),
      ),
    );
    return;
  }
  try {
    await store.setPin(pin);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'PIN saved. App lock will appear next time you open the app.',
          ),
        ),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save the PIN: $error')));
    }
  }
}

Future<String?> _showPinEntryDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
}) => showDialog<String>(
  context: context,
  builder: (context) =>
      _PinEntryDialog(title: title, label: label, action: action),
);

class _PinEntryDialog extends StatefulWidget {
  const _PinEntryDialog({
    required this.title,
    required this.label,
    required this.action,
  });

  final String title;
  final String label;
  final String action;

  @override
  State<_PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<_PinEntryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      decoration: InputDecoration(labelText: widget.label),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.action)),
    ],
  );

  void _submit() {
    final value = _controller.text.trim();
    if (RegExp(r'^\d{4,6}$').hasMatch(value)) {
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.pop(context, value);
    }
  }
}

Future<void> _showWallets(BuildContext context, TrackerStore store) async {
  final nameController = TextEditingController();
  final balanceController = TextEditingController(text: '0');
  String type = 'Cash';
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Wallets'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...store.wallets.map(
                  (wallet) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: Text(wallet.name),
                    subtitle: Text(
                      '${wallet.type} · opening ${_money(wallet.openingBalance)}',
                    ),
                    trailing: Text(_money(_walletBalance(store, wallet))),
                  ),
                ),
                const Divider(),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Wallet name'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const ['Cash', 'Bank', 'UPI', 'Wallet']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => type = value!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: balanceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Opening balance',
                    prefixText: '₹ ',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final balance = double.tryParse(balanceController.text.trim());
              if (name.isEmpty || balance == null || !balance.isFinite) return;
              try {
                await store.addWallet(
                  Wallet(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name,
                    type: type,
                    openingBalance: balance,
                  ),
                );
                if (context.mounted) Navigator.pop(context);
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not add wallet: $error')),
                  );
                }
              }
            },
            child: const Text('Add wallet'),
          ),
        ],
      ),
    ),
  );
  nameController.dispose();
  balanceController.dispose();
}

Future<void> _showCategories(BuildContext context, TrackerStore store) async {
  final controller = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Categories'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: store.categories
                  .map((value) => Chip(label: Text(value)))
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'New category'),
              onSubmitted: (_) => _addCategory(context, store, controller),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
        FilledButton(
          onPressed: () => _addCategory(context, store, controller),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  controller.dispose();
}

Future<void> _addCategory(
  BuildContext context,
  TrackerStore store,
  TextEditingController controller,
) async {
  final value = controller.text.trim();
  if (value.isEmpty) return;
  try {
    await store.addCategory(value);
    if (!context.mounted) return;
    controller.clear();
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not add category: $error')));
  }
}

Future<void> _showTransactionDetail(
  BuildContext context,
  TrackerStore store,
  MoneyTransaction item,
) async {
  final pageContext = context;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.isIncome ? 'Income' : 'Expense',
              style: const TextStyle(color: Colors.black54),
            ),
            Text(
              '${item.isIncome ? '+' : '−'}${_money(item.amount)}',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: item.isIncome ? _green : const Color(0xFFD65A53),
              ),
            ),
            const SizedBox(height: 8),
            Text('${item.category} · ${_formatDateTime(item.date)}'),
            Text('Wallet: ${_walletName(store.wallets, item.walletId)}'),
            if (item.note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(item.note),
            ],
            if (item.imageBase64 != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  base64Decode(item.imageBase64!),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            if (item.qrData != null) ...[
              const SizedBox(height: 8),
              const Text(
                'Scanned QR data',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SelectableText(item.qrData!),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      if (!pageContext.mounted) return;
                      await showModalBottomSheet<void>(
                        context: pageContext,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (context) =>
                            TransactionForm(store: store, transaction: item),
                      );
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD65A53),
                    ),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: sheetContext,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete transaction?'),
                          content: const Text('This cannot be undone.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true || !sheetContext.mounted) return;
                      try {
                        await store.deleteTransaction(item.id);
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      } catch (error) {
                        if (sheetContext.mounted) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(content: Text('Could not delete: $error')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.transaction,
    required this.wallet,
    required this.onTap,
  });
  final MoneyTransaction transaction;
  final String wallet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: transaction.isIncome
            ? const Color(0xFFE4F3EA)
            : const Color(0xFFFCEBE9),
        child: Icon(
          _categoryIcon(transaction.category),
          color: transaction.isIncome ? _green : const Color(0xFFD65A53),
          size: 20,
        ),
      ),
      title: Text(
        transaction.note.isEmpty ? transaction.category : transaction.note,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${transaction.category} · $wallet · ${_formatDateTime(transaction.date)}',
      ),
      trailing: Text(
        '${transaction.isIncome ? '+' : '−'}${_money(transaction.amount)}',
        style: TextStyle(
          color: transaction.isIncome ? _green : _ink,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 10),
    child: Column(
      children: [
        Icon(icon, size: 38, color: Colors.black38),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
      ],
    ),
  );
}

List<DateTime> _weekStarts(List<MoneyTransaction> transactions) {
  if (transactions.isEmpty) return [];
  final current = mondayOf(DateTime.now());
  final first = transactions
      .map((item) => mondayOf(item.date))
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final weeks = <DateTime>[];
  for (
    var start = current;
    !start.isBefore(first);
    start = start.subtract(const Duration(days: 7))
  ) {
    weeks.add(start);
  }
  return weeks;
}

double _sum(Iterable<MoneyTransaction> items, bool income) => items
    .where((item) => item.isIncome == income)
    .fold<double>(0, (total, item) => total + item.amount);

double _balanceAt(TrackerStore store, DateTime through) {
  final items = store.transactions
      .where((item) => !item.date.isAfter(through))
      .toList();
  return calculateBalance(store.wallets, items);
}

double _walletBalance(TrackerStore store, Wallet wallet) =>
    calculateBalance([wallet], store.transactions);

String _walletName(List<Wallet> wallets, String id) {
  for (final wallet in wallets) {
    if (wallet.id == id) return wallet.name;
  }
  return 'Unknown wallet';
}

String _money(double amount) => '₹${amount.toStringAsFixed(2)}';

String _number(double amount) => amount == amount.roundToDouble()
    ? amount.toStringAsFixed(0)
    : amount.toStringAsFixed(2);

Widget _smallAmount(String label, double amount, Color color) => Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      const SizedBox(height: 3),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          _money(amount),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    ],
  ),
);

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String _formatTime(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
}

String _formatDateTime(DateTime date) =>
    '${_formatDate(date)} · ${_formatTime(date)}';

IconData _categoryIcon(String category) => switch (category.toLowerCase()) {
  'food' => Icons.restaurant_outlined,
  'travel' => Icons.directions_bus_outlined,
  'bills' => Icons.receipt_outlined,
  'shopping' => Icons.shopping_bag_outlined,
  'salary' => Icons.payments_outlined,
  'business' => Icons.storefront_outlined,
  _ => Icons.currency_rupee,
};
