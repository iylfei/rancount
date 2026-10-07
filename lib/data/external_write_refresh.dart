import 'package:drift/drift.dart' as drift;
import 'db.dart';

/// A second Flutter engine can commit without notifying this Drift connection.
/// Keep the connection alive and re-run subscriptions against committed data.
void refreshExternalDatabaseWrites(BeeDatabase db) {
  db.notifyUpdates({
    for (final table in db.allTables) drift.TableUpdate(table.actualTableName),
  });
}
