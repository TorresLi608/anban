import 'package:flutter/material.dart';

import '../data/tumor_marker.dart';
import '../ui.dart';

class TumorMarkersEditor extends StatefulWidget {
  final List<TumorMarkerItem> items;
  final ValueChanged<List<TumorMarkerItem>> onChanged;
  final bool saving;

  const TumorMarkersEditor({
    super.key,
    required this.items,
    required this.onChanged,
    this.saving = false,
  });

  @override
  State<TumorMarkersEditor> createState() => _TumorMarkersEditorState();
}

class _TumorMarkersEditorState extends State<TumorMarkersEditor> {
  bool onlyFilledOrAbnormal = false;
  late List<TumorMarkerItem> _localItems;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _localItems = List.from(widget.items);
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant TumorMarkersEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items != oldWidget.items) {
      _localItems = List.from(widget.items);
      _syncControllers();
    }
  }

  void _syncControllers() {
    for (final item in _localItems) {
      if (!_controllers.containsKey(item.key)) {
        _controllers[item.key] = TextEditingController(text: item.value);
      } else if (_controllers[item.key]!.text != item.value) {
        _controllers[item.key]!.text = item.value;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _updateItem(TumorMarkerItem updated) {
    final idx = _localItems.indexWhere((e) => e.key == updated.key);
    if (idx != -1) {
      setState(() {
        _localItems[idx] = updated;
      });
      // 仅向外部回调新数据，无需触发外层整表全量重绘
      widget.onChanged(_localItems);
    }
  }

  void _markAllFilledNormal() {
    setState(() {
      _localItems = _localItems.map((e) {
        if (e.value.trim().isNotEmpty) {
          return e.copyWith(status: 'normal');
        }
        return e;
      }).toList();
    });
    widget.onChanged(_localItems);
  }

  Future<void> _editRefAndUnit(TumorMarkerItem item) async {
    // 弹窗前先收回输入法软键盘，防止键盘收起与弹窗展开双动画叠加掉帧
    final currentFocus = FocusScope.of(context);
    if (currentFocus.hasFocus) {
      currentFocus.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;

    final refController = TextEditingController(text: item.ref);
    final unitController = TextEditingController(text: item.unit);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('调整 ${item.abbr} 参考区间与单位'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '不同医院检验仪器与试剂不同，可按化验单所示调整：',
              style: TextStyle(fontSize: 12.5, color: muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: refController,
              decoration: const InputDecoration(
                labelText: '参考区间（如 0–5 或 < 3.4）',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: unitController,
              decoration: const InputDecoration(
                labelText: '单位（如 ng/mL, U/mL）',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final newRef = refController.text.trim();
      final newUnit = unitController.text.trim();
      final updated = item.copyWith(
        ref: newRef.isNotEmpty ? newRef : item.ref,
        unit: newUnit.isNotEmpty ? newUnit : item.unit,
        status: item.value.isNotEmpty
            ? TumorMarkerItem.detectStatus(item.value, newRef)
            : item.status,
      );
      _updateItem(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filledCount = _localItems.where((e) => e.value.trim().isNotEmpty).length;
    final highCount = _localItems.where((e) => e.status == 'high').length;
    final lowCount = _localItems.where((e) => e.status == 'low').length;

    final displayedItems = onlyFilledOrAbnormal
        ? _localItems
            .where((e) => e.value.trim().isNotEmpty || e.status.isNotEmpty)
            .toList()
        : _localItems;

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 顶部指示与操作工具栏
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F7F5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFB2DFDB), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.biotech, color: Color(0xFF00796B), size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '肿瘤标志物12项检验数据',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFB2DFDB)),
                      ),
                      child: Text(
                        '已填 $filledCount / ${_localItems.length}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF00796B),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (highCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$highCount 项偏高',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFC62828),
                        ),
                      ),
                    ),
                  if (lowCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$lowCount 项偏低',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFEF6C00),
                        ),
                      ),
                    ),
                  if (filledCount > 0 && highCount == 0 && lowCount == 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '已录入项均正常',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: widget.saving
                        ? null
                        : () => setState(() => onlyFilledOrAbnormal = !onlyFilledOrAbnormal),
                    icon: Icon(
                      onlyFilledOrAbnormal ? Icons.visibility : Icons.filter_alt_outlined,
                      size: 14,
                      color: const Color(0xFF00796B),
                    ),
                    label: Text(
                      onlyFilledOrAbnormal ? '显示全部12项' : '仅看已录入',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF00796B)),
                    ),
                  ),
                  if (filledCount > 0)
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: widget.saving ? null : _markAllFilledNormal,
                      child: const Text(
                        '设已填项为正常',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF00796B)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. 指标卡片列表
        if (displayedItems.isEmpty && onlyFilledOrAbnormal)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                '暂未录入任何标志物，请切换回“显示全部12项”填写',
                style: TextStyle(fontSize: 12.5, color: muted),
              ),
            ),
          )
        else
          for (int i = 0; i < displayedItems.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            RepaintBoundary(
              child: _buildItemCard(displayedItems[i]),
            ),
          ],
        const SizedBox(height: 12),

        // 3. 底部人文关怀与严谨医疗提示
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAF9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5EDE4)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 15, color: muted),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '提示：肿瘤标志物受炎症、生理周期及试剂差异影响，轻度超标不代表复发或确诊。所有指标请配合影像检查并严格遵从主治医师解读。',
                  style: TextStyle(fontSize: 11.5, color: muted, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildItemCard(TumorMarkerItem item) {
  final c = _controllers[item.key]!;

  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: item.status == 'high'
            ? const Color(0xFFFFCDD2)
            : item.status == 'low'
                ? const Color(0xFFFFE0B2)
                : const Color(0xFFE4EAE2),
        width: item.status == 'high' || item.status == 'low' ? 1.5 : 1,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x06000000),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题与状态
        Row(
          children: [
            Text(
              item.name,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                item.abbr,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00796B),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item.hint,
                style: const TextStyle(fontSize: 11, color: muted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _buildStatusBadge(item.status),
          ],
        ),
        const SizedBox(height: 10),

        // 输入行：数值与参考区间
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 5,
              child: TextFormField(
                controller: c,
                enabled: !widget.saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  hintText: '测定值',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                    color: muted,
                  ),
                  suffixText: item.unit,
                  suffixStyle: const TextStyle(
                    fontSize: 11.5,
                    color: muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onChanged: (val) {
                  final detected = val.trim().isEmpty
                      ? ''
                      : TumorMarkerItem.detectStatus(val, item.ref);
                  _updateItem(
                    item.copyWith(value: val.trim(), status: detected),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: InkWell(
                onTap: widget.saving ? null : () => _editRefAndUnit(item),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '参考: ',
                            style: TextStyle(fontSize: 10.5, color: muted),
                          ),
                          Expanded(
                            child: Text(
                              item.ref,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: ink,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.edit_outlined, size: 12, color: muted),
                        ],
                      ),
                      Text(
                        item.unit,
                        style: const TextStyle(fontSize: 10, color: muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 快捷状态切换行
        Row(
          children: [
            const Text(
              '快速状态: ',
              style: TextStyle(fontSize: 11, color: muted),
            ),
            const SizedBox(width: 4),
            _buildStatusChip(item, 'normal', '正常'),
            const SizedBox(width: 6),
            _buildStatusChip(item, 'high', '偏高 ↑'),
            const SizedBox(width: 6),
            _buildStatusChip(item, 'low', '偏低 ↓'),
            if (item.status.isNotEmpty || item.value.isNotEmpty) ...[
              const Spacer(),
              InkWell(
                onTap: widget.saving
                    ? null
                    : () {
                        c.clear();
                        _updateItem(item.copyWith(value: '', status: ''));
                      },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    '清空',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

  Widget _buildStatusBadge(String status) {
    return switch (status) {
      'high' => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            '偏高 ↑',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFFC62828),
            ),
          ),
        ),
      'low' => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            '偏低 ↓',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFFEF6C00),
            ),
          ),
        ),
      'normal' => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            '正常',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2E7D32),
            ),
          ),
        ),
      _ => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            '未测',
            style: TextStyle(fontSize: 10.5, color: muted),
          ),
        ),
    };
  }

  Widget _buildStatusChip(TumorMarkerItem item, String statusKey, String label) {
    final isSelected = item.status == statusKey;
    final color = statusKey == 'high'
        ? const Color(0xFFC62828)
        : statusKey == 'low'
            ? const Color(0xFFEF6C00)
            : const Color(0xFF2E7D32);

    return InkWell(
      onTap: widget.saving
          ? null
          : () {
              final newStatus = isSelected ? '' : statusKey;
              _updateItem(item.copyWith(status: newStatus));
            },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFE0E0E0),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? color : muted,
          ),
        ),
      ),
    );
  }
}
