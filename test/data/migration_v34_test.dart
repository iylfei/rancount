import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:beecount/data/db.dart';

void main() {
  test('v33 transaction remains intact and gains nullable draft/refund fields',
      () async {
    final dir = await Directory.systemTemp.createTemp('rancount-migration-');
    final file = File('${dir.path}/ledger.sqlite');
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY,
        ledger_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        note TEXT
      )
    ''');
    raw.execute("INSERT INTO transactions VALUES (1, 2, 'expense', 35, '旧记录')");
    raw.execute('PRAGMA user_version = 33');
    raw.dispose();

    final db = BeeDatabase.forTesting(NativeDatabase(file));
    try {
      final cols =
          await db.customSelect('PRAGMA table_info(transactions)').get();
      final names = cols.map((row) => row.read<String>('name')).toSet();
      expect(
          names,
          containsAll([
            'merchant',
            'item_description',
            'payment_channel',
            'refund_of_sync_id',
          ]));
      final row = await db
          .customSelect(
              'SELECT amount, note, merchant, refund_of_sync_id FROM transactions WHERE id = 1')
          .getSingle();
      expect(row.read<double>('amount'), 35);
      expect(row.read<String>('note'), '旧记录');
      expect(row.readNullable<String>('merchant'), isNull);
      expect(row.readNullable<String>('refund_of_sync_id'), isNull);
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
