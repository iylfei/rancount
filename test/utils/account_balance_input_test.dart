import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/utils/account_balance_input.dart';

void main() {
  test('credit debt is stored negative and survives reopening the editor', () {
    final stored = accountBalanceFromInput('credit_card', 763);
    expect(stored, -763);
    expect(accountBalanceForInput('credit_card', stored), 763);
    expect(
        accountBalanceFromInput(
            'credit_card', accountBalanceForInput('credit_card', stored)),
        stored);
  });

  test('prepaid credit and negative asset balances retain their sign', () {
    expect(accountBalanceFromInput('credit_card', -100), 100);
    expect(accountBalanceForInput('credit_card', 100), -100);
    expect(accountBalanceForInput('bank_card', -100), -100);
    expect(accountBalanceFromInput('bank_card', -100), -100);
    expect(accountBalanceFromInput('loan', 100), -100);
    expect(accountBalanceForInput('loan', -100), 100);
  });
}
