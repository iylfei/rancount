/// Credit-card inputs describe debt: positive is owed, negative is prepaid.
/// The database always stores a signed balance, so debt is negative there.
double accountBalanceFromInput(String type, double value) {
  if (type == 'credit_card') return -value;
  if (type == 'loan') return -value.abs();
  return value;
}

double accountBalanceForInput(String type, double balance) {
  if (type == 'credit_card') return -balance;
  if (type == 'loan') return balance.abs();
  return balance;
}
