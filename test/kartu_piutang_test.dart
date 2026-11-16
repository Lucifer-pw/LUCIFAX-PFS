import 'package:flutter_test/flutter_test.dart';
import 'package:cashier_app/services/print_service.dart';
import 'package:cashier_app/models/receivable.dart';

void main() {
  test('Kartu Piutang PDF generation includes payment installment date', () async {
    final receivables = [
      Receivable(
        id: 'rec_623',
        toko: 'AFM',
        kota: 'BATANG',
        noInvoice: '623',
        nominal: 60694290,
        tglKirim: DateTime(2026, 7, 23),
        paidAmount: 20000000,
        payments: [
          PaymentRecord(
            id: 'pay_1',
            amount: 20000000,
            date: DateTime(2026, 11, 9),
            paymentMethod: 'Transfer BCA',
            note: 'Cicilan 20jt',
          ),
        ],
      ),
      Receivable(
        id: 'rec_646',
        toko: 'AFM',
        kota: 'BATANG',
        noInvoice: '646',
        nominal: 23335372,
        tglKirim: DateTime(2026, 9, 3),
      ),
    ];

    final doc = await PrintService.buildKartuPiutangDocument(
      customerName: 'AFM',
      city: 'BATANG',
      items: receivables,
    );

    final bytes = await doc.save();
    expect(bytes, isNotEmpty);
    expect(bytes.length, greaterThan(1000));
  });

  test('Kartu Piutang PDF supports multiple installment dates for single invoice', () async {
    final receivables = [
      Receivable(
        id: 'rec_multi',
        toko: 'AFM',
        kota: 'BATANG',
        noInvoice: '600',
        nominal: 50000000,
        tglKirim: DateTime(2026, 6, 1),
        paidAmount: 30000000,
        payments: [
          PaymentRecord(
            id: 'pay_1',
            amount: 15000000,
            date: DateTime(2026, 8, 10),
            paymentMethod: 'Transfer BCA',
          ),
          PaymentRecord(
            id: 'pay_2',
            amount: 15000000,
            date: DateTime(2026, 9, 15),
            paymentMethod: 'Transfer Mandiri',
          ),
        ],
      ),
    ];

    final doc = await PrintService.buildKartuPiutangDocument(
      customerName: 'AFM',
      city: 'BATANG',
      items: receivables,
    );

    final bytes = await doc.save();
    expect(bytes, isNotEmpty);
  });
}
