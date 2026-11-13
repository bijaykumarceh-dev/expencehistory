import 'dart:convert';

class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalance,
  });

  final String id;
  final String name;
  final String type;
  final double openingBalance;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'openingBalance': openingBalance,
  };

  factory Wallet.fromJson(Map<String, Object?> json) => Wallet(
    id: json['id']! as String,
    name: json['name']! as String,
    type: json['type']! as String,
    openingBalance: (json['openingBalance']! as num).toDouble(),
  );
}

class MoneyTransaction {
  const MoneyTransaction({
    required this.id,
    required this.amount,
    required this.isIncome,
    required this.category,
    required this.walletId,
    required this.date,
    required this.note,
    this.imageBase64,
    this.qrData,
  });

  final String id;
  final double amount;
  final bool isIncome;
  final String category;
  final String walletId;
  final DateTime date;
  final String note;
  final String? imageBase64;
  final String? qrData;

  Map<String, Object?> toJson() => {
    'id': id,
    'amount': amount,
    'isIncome': isIncome,
    'category': category,
    'walletId': walletId,
    'date': date.toIso8601String(),
    'note': note,
    'imageBase64': imageBase64,
    'qrData': qrData,
  };

  factory MoneyTransaction.fromJson(Map<String, Object?> json) =>
      MoneyTransaction(
        id: json['id']! as String,
        amount: (json['amount']! as num).toDouble(),
        isIncome: json['isIncome']! as bool,
        category: json['category']! as String,
        walletId: json['walletId']! as String,
        date: DateTime.parse(json['date']! as String),
        note: json['note'] as String? ?? '',
        imageBase64: json['imageBase64'] as String?,
        qrData: json['qrData'] as String?,
      );
}

DateTime mondayOf(DateTime date) =>
    DateTime(date.year, date.month, date.day - (date.weekday - 1));

String weekStatus(double net) {
  if (net > 0) return 'Profit';
  if (net < 0) return 'Loss';
  return 'Break-even';
}

double calculateBalance(List<Wallet> wallets, List<MoneyTransaction> items) {
  return wallets.fold<double>(0, (sum, wallet) {
    final walletTransactions = items.where(
      (item) => item.walletId == wallet.id,
    );
    return sum +
        wallet.openingBalance +
        walletTransactions.fold<double>(
          0,
          (balance, item) =>
              balance + (item.isIncome ? item.amount : -item.amount),
        );
  });
}

Map<String, Object?> encodeSnapshot({
  required List<Wallet> wallets,
  required List<MoneyTransaction> transactions,
  required List<String> categories,
  required String? pinSalt,
  required String? pinHash,
}) => {
  'wallets': wallets.map((wallet) => wallet.toJson()).toList(),
  'transactions': transactions.map((item) => item.toJson()).toList(),
  'categories': categories,
  'pinSalt': pinSalt,
  'pinHash': pinHash,
};

List<Wallet> walletsFromSnapshot(Map<String, dynamic> snapshot) =>
    (snapshot['wallets'] as List<dynamic>? ?? [])
        .map((item) => Wallet.fromJson(Map<String, Object?>.from(item as Map)))
        .toList();

List<MoneyTransaction> transactionsFromSnapshot(
  Map<String, dynamic> snapshot,
) => (snapshot['transactions'] as List<dynamic>? ?? [])
    .map(
      (item) =>
          MoneyTransaction.fromJson(Map<String, Object?>.from(item as Map)),
    )
    .toList();

String snapshotToJson(Map<String, Object?> snapshot) => jsonEncode(snapshot);
