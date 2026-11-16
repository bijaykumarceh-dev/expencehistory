import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'tracker_models.dart';

Future<Uint8List> buildWeeklyReportPdf({
  required DateTime weekStart,
  required List<MoneyTransaction> transactions,
  required List<Wallet> wallets,
  required double openingBalance,
  required double closingBalance,
}) async {
  final weekEnd = weekStart.add(const Duration(days: 6));
  final sortedTransactions = [...transactions]
    ..sort((a, b) => a.date.compareTo(b.date));
  final income = _sum(sortedTransactions, true);
  final expenses = _sum(sortedTransactions, false);
  final categories = <String, double>{};
  for (final transaction in sortedTransactions.where(
    (item) => !item.isIncome,
  )) {
    categories.update(
      transaction.category,
      (amount) => amount + transaction.amount,
      ifAbsent: () => transaction.amount,
    );
  }
  final sortedCategories = categories.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final document = pw.Document(
    title: 'KhataFlow Weekly Report',
    author: 'KhataFlow',
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Container(
        alignment: pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.green700, width: 1.5),
          ),
        ),
        child: pw.Text(
          'KHATAFLOW',
          style: pw.TextStyle(
            color: PdfColors.green700,
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 9),
        ),
      ),
      build: (context) => [
        pw.SizedBox(height: 18),
        pw.Text(
          'Weekly report',
          style: pw.TextStyle(
            color: PdfColors.grey900,
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          '${_formatDate(weekStart)} - ${_formatDate(weekEnd)}',
          style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 11),
        ),
        pw.SizedBox(height: 18),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: const pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(1),
              1: const pw.FlexColumnWidth(1),
            },
            children: [
              _summaryRow('Opening balance', openingBalance),
              _summaryRow('Income', income),
              _summaryRow('Expenses', expenses),
              _summaryRow('Net', income - expenses),
              _summaryRow('Closing balance', closingBalance),
            ],
          ),
        ),
        if (sortedCategories.isNotEmpty) ...[
          pw.SizedBox(height: 22),
          pw.Text(
            'Expenses by category',
            style: pw.TextStyle(
              color: PdfColors.grey900,
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            children: sortedCategories
                .map(
                  (entry) => _tableRow(
                    [entry.key, _formatAmount(entry.value)],
                    rightAligned: {1},
                  ),
                )
                .toList(),
          ),
        ],
        pw.SizedBox(height: 22),
        pw.Text(
          'Transactions (${sortedTransactions.length})',
          style: pw.TextStyle(
            color: PdfColors.grey900,
            fontSize: 15,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        if (sortedTransactions.isEmpty)
          pw.Text(
            'No transactions for this week.',
            style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
          )
        else
          pw.Table(
            border: pw.TableBorder(
              horizontalInside: const pw.BorderSide(
                color: PdfColors.grey300,
                width: 0.5,
              ),
            ),
            columnWidths: {
              0: const pw.FixedColumnWidth(68),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FixedColumnWidth(74),
              3: const pw.FixedColumnWidth(92),
            },
            children: [
              _tableRow(['Date', 'Entry', 'Wallet', 'Amount'], isHeader: true),
              ...sortedTransactions.map((transaction) {
                final wallet = wallets
                    .where((item) => item.id == transaction.walletId)
                    .firstOrNull;
                final note = transaction.note.trim();
                return _tableRow(
                  [
                    _formatDateTime(transaction.date),
                    '${transaction.isIncome ? 'Income' : 'Expense'} - ${transaction.category}'
                        '${note.isEmpty ? '' : '\n$note'}',
                    wallet?.name ?? 'Unknown',
                    '${transaction.isIncome ? '+' : '-'}${_formatAmount(transaction.amount)}',
                  ],
                  rightAligned: {3},
                );
              }),
            ],
          ),
      ],
    ),
  );
  return document.save();
}

pw.TableRow _summaryRow(String label, double amount) => pw.TableRow(
  children: [
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
    ),
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Text(
        _formatAmount(amount),
        textAlign: pw.TextAlign.right,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
    ),
  ],
);

pw.TableRow _tableRow(
  List<String> cells, {
  bool isHeader = false,
  Set<int> rightAligned = const {},
}) => pw.TableRow(
  decoration: isHeader
      ? const pw.BoxDecoration(color: PdfColors.green700)
      : null,
  children: [
    for (var index = 0; index < cells.length; index++)
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        child: pw.Text(
          cells[index],
          textAlign: rightAligned.contains(index)
              ? pw.TextAlign.right
              : pw.TextAlign.left,
          style: pw.TextStyle(
            color: isHeader ? PdfColors.white : PdfColors.grey900,
            fontSize: isHeader ? 9 : 8,
            fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
  ],
);

double _sum(Iterable<MoneyTransaction> transactions, bool income) =>
    transactions
        .where((item) => item.isIncome == income)
        .fold<double>(0, (total, item) => total + item.amount);

String _formatAmount(double amount) => 'INR ${amount.toStringAsFixed(2)}';

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')} ${_month(date.month)} ${date.year}';

String _formatDateTime(DateTime date) =>
    '${_formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String _month(int month) => const [
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
][month - 1];
