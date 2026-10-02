import 'package:flutter/foundation.dart';

import 'models.dart';
import 'planning.dart';
import 'vault.dart';

class CareStore extends ChangeNotifier {
  LocalVault vault;
  CareData data;
  Map<String, List<String>> healthOptions = Map.from(defaultHealthOptions);
  Future<void> Function(CareData, LocalVault)? publish;
  Future<void> _pending = Future.value();
  CareStore(this.vault, this.data);
  Future<void> exclusive(Future<void> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<void> switchVault(LocalVault next, CareData nextData) =>
      exclusive(() => replaceVault(next, nextData));

  // Called inside exclusive when a cloud load and account switch must be atomic.
  Future<void> replaceVault(LocalVault next, CareData nextData) async {
    final previous = vault;
    vault = next;
    data = nextData;
    notifyListeners();
    await previous.close();
  }

  List<CareRecord> records(String kind) =>
      data.records.where((r) => r.kind == kind).toList()
        ..sort((a, b) => b.at.compareTo(a.at));
  Future<void> change(CareData Function(CareData) update) {
    final result = _pending.then((_) async {
      final next = update(data);
      await publish?.call(next, vault);
      await vault.save(next);
      data = next;
      notifyListeners();
    });
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<void> put(CareRecord record) {
    record.validate();
    return change((d) {
      if (record.kind == 'journeyEntry' &&
          !d.records.any(
            (r) => r.kind == 'journey' && r.id == record.text('journeyId'),
          )) {
        throw StateError('所属行程不存在');
      }
      return d.copy(
        records: [...d.records.where((r) => r.id != record.id), record],
      );
    });
  }

  Future<void> remove(CareRecord record) {
    if (['journey', 'journeyEntry'].contains(record.kind)) {
      throw StateError('行程记录不支持删除');
    }
    return change(
      (d) =>
          d.copy(records: d.records.where((r) => r.id != record.id).toList()),
    );
  }

  Future<void> profile(Map<String, String> values) =>
      change((d) => d.copy(profile: values));
  Future<void> settings(Map<String, String> values) =>
      change((d) => d.copy(settings: {...d.settings, ...values}));
  Future<void> take(PlannedDose dose, String effect) => change((d) {
    if (d.records.any(
      (r) => r.kind == 'dose' && r.text('doseKey') == dose.key,
    )) {
      throw StateError('这次用药已经打卡');
    }
    if (!d.records.any(
      (r) => r.kind == 'medication' && r.id == dose.medication.id,
    )) {
      throw StateError('用药计划已移除');
    }
    return d.copy(
      records: [
        ...d.records,
        CareRecord(
          kind: 'dose',
          fields: {
            'medicationId': dose.medication.id,
            'doseKey': dose.key,
            'name': dose.medication.text('name'),
            'dose': dose.medication.text('dose'),
            'scheduled': dose.scheduled.toIso8601String(),
            'effect': effect,
          },
        ),
      ],
    );
  });
  Future<void> restore(Map<String, dynamic> backup) {
    final result = _pending.then((_) async {
      if (publish == null) {
        data = await vault.restore(backup);
        notifyListeners();
        return;
      }
      final staged = await LocalVault.memory();
      try {
        final next = await staged.restore(backup);
        await publish?.call(next, staged);
        final previous = vault;
        vault = staged;
        data = next;
        notifyListeners();
        await previous.close();
      } catch (_) {
        await staged.close();
        rethrow;
      }
    });
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<void> clear() {
    final result = _pending.then((_) async {
      await publish?.call(CareData(), vault);
      await vault.clear();
      data = CareData();
      notifyListeners();
    });
    _pending = result.catchError((Object _) {});
    return result;
  }
}
