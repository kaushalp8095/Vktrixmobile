import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/screens/common.dart';

void main() {
  test('ISO timestamps are shown as their original calendar date', () {
    expect(dateOnly('2026-10-09T00:00:00.000Z'), '2026-10-09');
    expect(dateOnly('2026-10-09'), '2026-10-09');
    expect(dateOnly(DateTime.utc(2026, 10, 9)), '2026-10-09');
  });

  test('missing and unparseable dates remain safe to display', () {
    expect(dateOnly(null), '—');
    expect(dateOnly(''), '—');
    expect(dateOnly('legacy date'), 'legacy date');
  });
}
