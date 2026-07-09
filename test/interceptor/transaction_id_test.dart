import 'package:falconer/src/interceptor/transaction_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ids are unique and the counter increments monotonically', () {
    final a = TransactionId.next();
    final b = TransactionId.next();
    expect(a, isNot(b));

    final epochA = a.split('-').first;
    final epochB = b.split('-').first;
    expect(epochA, epochB, reason: 'session epoch is stable within a run');

    final nA = int.parse(a.split('-').last);
    final nB = int.parse(b.split('-').last);
    expect(nB, nA + 1);
  });
}
