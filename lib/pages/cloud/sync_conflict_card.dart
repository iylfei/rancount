import 'dart:convert';
import 'package:flutter/material.dart';
import '../../cloud/sync/sync_engine.dart';
import '../../data/db.dart';

class SyncConflictCard extends StatefulWidget {
  final SyncEngine engine;
  const SyncConflictCard({super.key, required this.engine});

  @override
  State<SyncConflictCard> createState() => _SyncConflictCardState();
}

class _SyncConflictCardState extends State<SyncConflictCard> {
  late Stream<List<SyncPullError>> _conflicts;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _conflicts = widget.engine.watchConflicts();
  }

  @override
  void didUpdateWidget(covariant SyncConflictCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine) {
      _conflicts = widget.engine.watchConflicts();
    }
  }

  String _describe(Map<String, dynamic> version) {
    if (version['action'] == 'delete') return '已删除';
    const names = {
      'name': '名称',
      'type': '类型',
      'amount': '金额',
      'currencyCode': '币种',
      'happenedAt': '日期',
      'categoryName': '分类',
      'accountName': '账户',
      'toAccountName': '转入账户',
      'note': '备注',
      'merchant': '商家',
      'itemDescription': '商品',
      'paymentChannel': '支付渠道',
      'initialBalance': '初始余额',
      'excludeFromStats': '不计收支',
      'excludeFromBudget': '不计预算',
    };
    final lines = names.entries
        .where((e) => version[e.key] != null)
        .map((e) => '${e.value}：${version[e.key]}')
        .toList();
    return lines.isEmpty ? '记录的其他字段有修改' : lines.join('\n');
  }

  Future<void> _review(SyncPullError conflict) async {
    setState(() => _busy = true);
    try {
      final local = await widget.engine.localConflictVersion(conflict);
      final raw = jsonDecode(conflict.rawChangeJson) as Map<String, dynamic>;
      final remote = raw['action'] == 'delete'
          ? <String, dynamic>{'action': 'delete'}
          : Map<String, dynamic>.from(raw['payload'] as Map? ?? {});
      if (!mounted) return;
      final keepLocal = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('选择要保留的版本'),
                content: SingleChildScrollView(
                    child: Text(
                        '本机\n${_describe(local)}\n\n云端\n${_describe(remote)}\n\n选择后将使用该版本继续同步。')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('稍后处理')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('使用云端')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('保留本机')),
                ],
              ));
      if (keepLocal == null) return;
      await widget.engine.resolveConflict(conflict,
          keepLocal: keepLocal, expectedLocal: local);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('暂未处理：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<SyncPullError>>(
        stream: _conflicts,
        builder: (context, snapshot) {
          final rows = <String, SyncPullError>{};
          for (final row in snapshot.data ?? <SyncPullError>[]) {
            rows.putIfAbsent(
                '${row.entityType}/${row.entitySyncId}', () => row);
          }
          if (rows.isEmpty) return const SizedBox.shrink();
          return Card(
              child: Column(children: [
            const ListTile(
                title: Text('同步冲突'), subtitle: Text('本机修改已保留。处理以下差异后会继续上传。')),
            for (final row in rows.values)
              ListTile(
                  title: Text(
                      row.entityType == 'transaction' ? '账单修改冲突' : '记录修改冲突'),
                  subtitle:
                      Text(row.action == 'delete' ? '云端已删除这条记录' : '本机和云端都有修改'),
                  trailing: TextButton(
                      onPressed: _busy ? null : () => _review(row),
                      child: const Text('查看差异'))),
          ]));
        },
      );
}
