import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../data/planning.dart';
import '../ui.dart';
import '../data/medical.dart';
import 'archive_picker.dart';

class FieldSpec {
  final String key, label;
  final List<String> choices;
  final String type, initial;
  final bool required;
  const FieldSpec(
    this.key,
    this.label, {
    this.choices = const [],
    this.type = 'text',
    this.initial = '',
    this.required = false,
  });
}

const specifications = <String, List<FieldSpec>>{
  'folder': [FieldSpec('title', '文件夹名称 *', required: true)],
  'document': [
    FieldSpec('title', '档案名称 *', required: true),
    FieldSpec('category', '资料分类'),
    FieldSpec('note', '备注', type: 'multiline'),
  ],
  'visit': [
    FieldSpec(
      'visitType',
      '看诊类型 *',
      choices: ['门诊', '住院'],
      initial: '门诊',
      required: true,
    ),
    FieldSpec('title', '看诊名称 *', initial: '看诊记录', required: true),
    FieldSpec('hospital', '医院'),
    FieldSpec('department', '科室'),
    FieldSpec('doctor', '医生'),
    FieldSpec('reason', '就诊原因 / 入院原因', type: 'multiline'),
    FieldSpec('findings', '诊疗结果 / 住院经过', type: 'multiline'),
    FieldSpec('plan', '后续安排', type: 'multiline'),
    FieldSpec('dischargeAt', '出院时间（住院可选）', type: 'datetime'),
    FieldSpec('archiveIds', '关联档案', type: 'archives'),
    FieldSpec('note', '补充备注', type: 'multiline'),
  ],
  'instruction': [
    FieldSpec('content', '医嘱内容 *', type: 'multiline', required: true),
    FieldSpec('title', '标题', initial: '临时医嘱'),
    FieldSpec('doctor', '医生 / 来源'),
    FieldSpec('visitId', '关联看诊', type: 'visit'),
  ],
  'pain': [
    FieldSpec(
      'location',
      '疼痛部位',
      choices: ['上腹', '腰背', '全腹', '全身', '其他'],
      initial: '上腹',
    ),
    FieldSpec(
      'type',
      '疼痛类型',
      choices: ['隐痛', '胀痛', '绞痛', '刺痛', '爆发痛'],
      initial: '隐痛',
    ),
    FieldSpec(
      'trigger',
      '出现时的情况',
      choices: ['空腹', '进食后', '夜间', '翻身', '无诱因'],
      initial: '无诱因',
    ),
    FieldSpec(
      'relief',
      '缓解情况',
      choices: ['未缓解', '自行缓解', '用药缓解'],
      initial: '未缓解',
    ),
    FieldSpec('note', '补充说明', type: 'multiline'),
  ],
  'symptom': [
    FieldSpec('name', '症状', choices: symptomNames, initial: '腹胀'),
    FieldSpec('severity', '程度', choices: ['轻', '中', '重'], initial: '轻'),
    FieldSpec(
      'duration',
      '持续时间',
      choices: ['刚出现', '不足 1 小时', '1–6 小时', '超过 6 小时', '持续多日'],
      initial: '刚出现',
    ),
    FieldSpec(
      'impact',
      '对进食 / 睡眠的影响',
      choices: ['无明显影响', '影响进食', '影响睡眠', '两者均影响'],
      initial: '无明显影响',
    ),
    FieldSpec('note', '补充说明', type: 'multiline'),
  ],
  'weight': [
    FieldSpec('weight', '体重（kg）*', type: 'number', required: true),
    FieldSpec('temperature', '体温（℃）', type: 'number'),
    FieldSpec('food', '进食情况'),
    FieldSpec('note', '补充说明', type: 'multiline'),
  ],
  'stool': [
    FieldSpec('status', '排便情况 *', type: 'multi', required: true),
    FieldSpec('note', '补充说明', type: 'multiline'),
  ],
  'urine': [
    FieldSpec('status', '排便情况 *', type: 'multi', required: true),
    FieldSpec('color', '颜色', type: 'multi'),
    FieldSpec('appearance', '性状', type: 'multi'),
    FieldSpec('note', '补充说明', type: 'multiline'),
  ],
  'journey': [
    FieldSpec(
      'category',
      '分类 *',
      choices: ['picc', 'port', 'chemo'],
      required: true,
    ),
    FieldSpec('last', '上次执行时间 *', type: 'datetime', required: true),
    FieldSpec('next', '下次执行时间 *', type: 'datetime', required: true),
    FieldSpec('note', '补充说明', type: 'multiline'),
  ],
  'journeyEntry': [
    FieldSpec('last', '上次执行时间 *', type: 'datetime', required: true),
    FieldSpec('next', '下次执行时间 *', type: 'datetime', required: true),
    FieldSpec('note', '补充说明', type: 'multiline'),
  ],
};
const kindNames = {
  'folder': '文件夹',
  'document': '档案',
  'visit': '看诊记录',
  'instruction': '医嘱',
  'weight': '体重',
  'stool': '大便',
  'urine': '小便',
  'pain': '疼痛',
  'symptom': '症状',
  'journey': '化疗及维护行程',
  'journeyEntry': '行程记录',
};

Future<void> editRecord(
  BuildContext context,
  CareStore store,
  String kind, {
  CareRecord? record,
  Map<String, String> initial = const {},
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 680),
    builder: (_) =>
        RecordForm(store: store, kind: kind, record: record, initial: initial),
  );
}

class RecordForm extends StatefulWidget {
  final CareStore store;
  final String kind;
  final CareRecord? record;
  final Map<String, String> initial;
  const RecordForm({
    super.key,
    required this.store,
    required this.kind,
    this.record,
    required this.initial,
  });
  @override
  State<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<RecordForm> {
  final key = GlobalKey<FormState>();
  final controllers = <String, TextEditingController>{};
  late DateTime at;
  double score = 3;
  bool saving = false;
  String? error;
  List<Map<String, String>> photos = [];
  bool get supportsPhotos => [
    'weight',
    'stool',
    'urine',
    'journey',
    'journeyEntry',
  ].contains(widget.kind);
  @override
  void initState() {
    super.initState();
    at = widget.record?.at ?? DateTime.now();
    photos = widget.record == null ? [] : photosOf(widget.record!);
    score = widget.record?.number('score') ?? 3;
    for (final spec in specifications[widget.kind]!) {
      controllers[spec.key] = TextEditingController(
        text:
            widget.record?.fields[spec.key] ??
            widget.initial[spec.key] ??
            (spec.key == 'start' ? dayKey(DateTime.now()) : spec.initial),
      );
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!key.currentState!.validate()) {
      return;
    }
    setState(() => saving = true);
    try {
      final record = CareRecord(
        id: widget.record?.id,
        kind: widget.kind,
        at: at,
        fields: {
          ...widget.record?.fields ?? {},
          ...widget.initial,
          ...controllers.map((k, v) => MapEntry(k, v.text.trim())),
          if (widget.kind == 'pain') 'score': score.round().toString(),
          if (supportsPhotos) 'photos': jsonEncode(photos),
        },
      );
      await widget.store.put(record);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e.toString().replaceFirst('FormatException: ', ''),
        );
      }
    }
    if (mounted) {
      setState(() => saving = false);
    }
  }

  Future<void> pickAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: at,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(at),
    );
    if (time != null && mounted) {
      setState(
        () => at = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      child: Form(
        key: key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.record == null ? '添加' : '编辑'}${kindNames[widget.kind]}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.kind == 'medication')
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: Note(
                          '仅记录医生已开具的用药方案。漏服或出现不适时，请联系医护，不要自行补服、加量或停药。',
                        ),
                      ),
                    if (widget.kind != 'folder')
                      OutlinedButton.icon(
                        onPressed: saving ? null : pickAt,
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(
                          '${widget.kind == 'visit'
                              ? '看诊 / 入院时间'
                              : widget.kind == 'handover'
                              ? '班次日期'
                              : '记录时间'}  ${dayKey(at)} ${clockText(at)}',
                        ),
                      ),
                    const SizedBox(height: 20),
                    if (widget.kind == 'pain') ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('此刻的疼痛程度'),
                          Text(
                            '${score.round()} / 10',
                            style: const TextStyle(
                              fontSize: 28,
                              color: pine,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: score,
                        min: 0,
                        max: 10,
                        divisions: 10,
                        label: '${score.round()} 分',
                        onChanged: (v) => setState(() => score = v),
                        semanticFormatterCallback: (v) =>
                            '疼痛 ${v.round()} 分，共 10 分',
                      ),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '0 · 无痛',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                          Text(
                            '10 · 最剧烈',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                      if (score >= 7)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Note(
                            '疼痛明显，请尽快联系医护；如伴意识改变、呼吸困难等，立即寻求急救。',
                            urgent: true,
                          ),
                        ),
                      const SizedBox(height: 22),
                    ],
                    for (final spec in specifications[widget.kind]!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 22),
                        child: field(spec),
                      ),
                    if (supportsPhotos) ...[
                      Text('图片（${photos.length}/9）'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final photo in photos)
                            SizedBox(
                              width: 96,
                              child: Column(
                                children: [
                                  FutureBuilder(
                                    future: widget.store.vault.attachment(
                                      photo['id']!,
                                    ),
                                    builder: (context, snapshot) =>
                                        snapshot.hasData
                                        ? InkWell(
                                            onTap: () => showDialog<void>(
                                              context: context,
                                              builder: (c) => Dialog(
                                                child: InteractiveViewer(
                                                  child: Image.memory(
                                                    snapshot.data!,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            child: Image.memory(
                                              snapshot.data!,
                                              width: 90,
                                              height: 90,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  const Icon(
                                                    Icons.broken_image,
                                                  ),
                                            ),
                                          )
                                        : const SizedBox(
                                            height: 90,
                                            child: Center(
                                              child: Icon(Icons.image),
                                            ),
                                          ),
                                  ),
                                  TextButton(
                                    onPressed: saving
                                        ? null
                                        : () => setState(
                                            () => photos.remove(photo),
                                          ),
                                    child: const Text('移除'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      OutlinedButton.icon(
                        onPressed: saving || photos.length >= 9
                            ? null
                            : addPhotos,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('上传图片（最多9张）'),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Note(error!, urgent: true),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(saving ? '正在加密保存…' : '保存记录'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> addPhotos() async {
    if (saving) return;
    setState(() => saving = true);
    await attempt(context, () async {
      final picked = await ImagePicker().pickMultiImage(
        maxWidth: 2400,
        imageQuality: 85,
      );
      if (photos.length + picked.length > 9) {
        throw const FormatException('每条记录最多上传 9 张图片');
      }
      final added = <Map<String, String>>[];
      for (final file in picked) {
        if (await file.length() > 20 * 1024 * 1024) {
          throw const FormatException('单张图片不能超过20 MB');
        }
        final id = await widget.store.vault.addAttachment(
          await file.readAsBytes(),
        );
        added.add({'id': id, 'name': file.name});
      }
      if (mounted) setState(() => photos.addAll(added));
    });
    if (mounted) setState(() => saving = false);
  }

  Widget field(FieldSpec spec) {
    final c = controllers[spec.key]!;
    if (spec.type == 'archives') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('已关联 ${selectedValues(c.text).length} 项档案或文件夹'),
          OutlinedButton.icon(
            onPressed: saving
                ? null
                : () async {
                    final ids = await selectArchives(
                      context,
                      widget.store,
                      selected: selectedValues(c.text).toSet(),
                    );
                    if (ids != null && mounted) {
                      setState(() => c.text = jsonEncode(ids.toList()));
                    }
                  },
            icon: const Icon(Icons.link),
            label: const Text('选择关联档案'),
          ),
        ],
      );
    }
    if (spec.type == 'visit') {
      return DropdownButtonFormField<String>(
        initialValue: c.text,
        isExpanded: true,
        decoration: InputDecoration(labelText: spec.label),
        items: [
          const DropdownMenuItem(value: '', child: Text('不关联看诊')),
          for (final visit in widget.store.records('visit'))
            DropdownMenuItem(
              value: visit.id,
              child: Text(
                '${dayKey(visit.at)} ${medicalTitle(visit)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: saving
            ? null
            : (value) => setState(() => c.text = value ?? ''),
      );
    }
    final optionKey = widget.kind == 'stool'
        ? 'stoolStatus'
        : switch (spec.key) {
            'status' => 'urineStatus',
            'color' => 'urineColor',
            _ => 'urineAppearance',
          };
    final choices = spec.type == 'multi'
        ? widget.store.healthOptions[optionKey] ?? []
        : spec.choices;
    if (spec.type == 'multi' || choices.isNotEmpty) {
      final selected = spec.type == 'multi' ? selectedValues(c.text) : [c.text];
      return FormField<String>(
        validator: (_) =>
            spec.required &&
                (spec.type == 'multi'
                    ? selectedValues(c.text).isEmpty
                    : c.text.isEmpty)
            ? '请选择${spec.label}'
            : null,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              spec.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final choice in {
                  ...choices,
                  ...selected.where((v) => v.isNotEmpty),
                })
                  FilterChip(
                    label: Text(
                      spec.key == 'category'
                          ? journeyCategories[choice] ?? choice
                          : choice,
                    ),
                    selected: selected.contains(choice),
                    onSelected: saving
                        ? null
                        : (checked) => setState(() {
                            if (spec.type == 'multi') {
                              checked
                                  ? selected.add(choice)
                                  : selected.remove(choice);
                              c.text = jsonEncode(selected);
                            } else {
                              c.text = checked ? choice : '';
                            }
                            state.didChange(c.text);
                          }),
                  ),
              ],
            ),
            if (state.hasError)
              Text(state.errorText!, style: const TextStyle(color: danger)),
          ],
        ),
      );
    }
    return TextFormField(
      controller: c,
      enabled: !saving,
      readOnly: spec.type == 'datetime',
      maxLength: spec.type == 'multiline'
          ? 10000
          : widget.kind == 'folder'
          ? 120
          : 150,
      maxLines: spec.type == 'multiline' ? 3 : 1,
      keyboardType: spec.type == 'number'
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: spec.label,
        counterText: '',
        suffixIcon:
            spec.type == 'datetime' && !spec.required && c.text.isNotEmpty
            ? IconButton(
                onPressed: saving ? null : () => setState(c.clear),
                icon: const Icon(Icons.clear),
                tooltip: '清除时间',
              )
            : null,
      ),
      onTap: spec.type != 'datetime'
          ? null
          : () async {
              final initial = DateTime.tryParse(c.text) ?? DateTime.now();
              final date = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (date == null || !mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(initial),
              );
              if (time != null && mounted) {
                setState(
                  () => c.text = DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  ).toIso8601String(),
                );
              }
            },
      validator: (v) => spec.required && (v?.trim().isEmpty ?? true)
          ? '请填写${spec.label}'
          : null,
    );
  }
}
