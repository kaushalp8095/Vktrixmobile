// Money formatting: ledger me paise hain (validation 2 decimal allow karta hai),
// to har screen par wahi amount dikhna chahiye. Pehle `rs()` 0 decimal par round
// karta tha — 12,500.50 ka bill / due ₹12,501 dikhta tha.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/api.dart';

void main() {
  test('whole amounts stay clean — no forced ".00"', () {
    expect(rs(12500), '₹12,500');
    expect(rs('12500'), '₹12,500');
    expect(rs(0), '₹0');
    expect(rs(1250000), '₹12,50,000');
    expect(rs('21500.00'), '₹21,500');
  });

  test('paise appear only when they exist', () {
    expect(rs(12500.5), '₹12,500.50');
    expect(rs('12500.5'), '₹12,500.50');
    expect(rs(12500.05), '₹12,500.05');
    expect(rs(0.5), '₹0.50');
    expect(rs(1.99), '₹1.99');
    expect(rs(9999999999.99), '₹9,99,99,99,999.99');
  });

  test('rounding is to the nearest paisa, not to the rupee', () {
    expect(rs(12500.494), '₹12,500.49');
    expect(rs(12.344), '₹12.34');
    expect(rs(12.345), '₹12.35');
  });

  test('negatives (refund/balance) keep the sign outside the symbol', () {
    expect(rs(-12500.5), '-₹12,500.50');
    expect(rs(-12500), '-₹12,500');
    expect(rs(-0.0001), '₹0'); // -0.00 dikhane ka koi matlab nahi
  });

  test('garbage never crashes a bill', () {
    expect(rs(null), '₹0');
    expect(rs(''), '₹0');
    expect(rs('abc'), '₹0');
  });
}
