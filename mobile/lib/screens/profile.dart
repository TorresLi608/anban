import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../data/vault.dart';
import '../services/reminders.dart';

import '../services/account.dart';
import '../ui.dart';
import 'settings.dart';

class ProfilePage extends StatefulWidget {
  final CareStore store;
  final ReminderService reminders;
  final bool loginOnly;
  const ProfilePage({
    super.key,
    required this.store,
    required this.reminders,
    this.loginOnly = false,
  });
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool busy = false;
  Future<void> run(Future<void> Function() action) async {
    if (busy) {
      return;
    }
    setState(() => busy = true);
    await attempt(context, action);
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> editProfile() async {
    const names = {
      'name': '患者称呼',
      'age': '年龄',
      'diagnosis': '确诊日期',
      'doctor': '主治医生',
      'hospital': '常用医院',
      'note': '基础病情备注',
    };
    final controllers = {
      for (final k in names.keys)
        k: TextEditingController(text: widget.store.data.profile[k] ?? ''),
    };
    final key = GlobalKey<FormState>();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('患者基础档案'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in names.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextFormField(
                        controller: controllers[e.key],
                        decoration: InputDecoration(labelText: e.value),
                        maxLength: e.key == 'note' ? 2000 : 100,
                        maxLines: e.key == 'note' ? 3 : 1,
                        keyboardType: e.key == 'age'
                            ? TextInputType.number
                            : TextInputType.text,
                        readOnly: e.key == 'diagnosis',
                        onTap: e.key == 'diagnosis'
                            ? () async {
                                final date = await showDatePicker(
                                  context: c,
                                  initialDate:
                                      DateTime.tryParse(
                                        controllers['diagnosis']!.text,
                                      ) ??
                                      DateTime.now(),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                );
                                if (date != null) {
                                  controllers['diagnosis']!.text = dayKey(date);
                                }
                              }
                            : null,
                        validator: (v) =>
                            e.key == 'age' &&
                                v!.isNotEmpty &&
                                (int.tryParse(v) == null ||
                                    int.parse(v) < 0 ||
                                    int.parse(v) > 130)
                            ? '请输入有效年龄'
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                Navigator.pop(
                  c,
                  controllers.map((k, v) => MapEntry(k, v.text.trim())),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) {
      await widget.store.profile(result);
    }
    // Dialog route may animate out after pop; dispose on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in controllers.values) {
        c.dispose();
      }
    });
  }

  Future<String?> password({bool creating = false}) async {
    final c = TextEditingController();
    final key = GlobalKey<FormState>();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(creating ? '设置备份密码' : '输入备份密码'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '密码仅用于本机加解密，不会发送到服务器。请妥善保存，遗失后无法恢复。',
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: c,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: '至少 6 个字符'),
                validator: (v) =>
                    (v?.runes.length ?? 0) < 6 ? '请使用至少 6 个字符' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                Navigator.pop(ctx, c.text);
              }
            },
            child: const Text('继续'),
          ),
        ],
      ),
    );
    return value;
  }

  Future<void> backup() async {
    final secret = await password(creating: true);
    if (secret == null) {
      return;
    }
    final backup = await widget.store.vault.backup(widget.store.data);
    final envelope = await sealBackup(backup, secret);
    final path = await FilePicker.saveFile(
      fileName: '安伴-${dayKey(DateTime.now())}.anban',
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
    );
    if (mounted) {
      toast(context, path == null ? '已关闭保存窗口；请确认下载或保存结果' : '加密备份已保存');
    }
  }

  Future<void> restore() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null) {
      return;
    }
    if ((await picked.length() ?? 0) > 100 * 1024 * 1024) {
      throw StateError('备份文件超过 100 MB');
    }
    final bytes = await picked.readAsBytes();
    if (!mounted) {
      return;
    }
    final secret = await password();
    if (secret == null) {
      return;
    }
    final backup = await openBackup(
      Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes))),
      secret,
    );
    final restored = CareData.fromJson(backup['data']);
    if (!mounted ||
        !await confirm(
          context,
          '恢复 ${restored.records.length} 条记录？',
          '将上传并替换当前账号云端资料与附件。建议先导出当前资料备份。密码或文件错误时不会覆盖现有数据。',
          action: '替换并恢复',
        )) {
      return;
    }
    await widget.store.restore(backup);
    if (mounted) {
      toast(context, '加密备份已恢复');
    }
  }

  Future<void> connect() async {
    final username = TextEditingController();
    final secret = TextEditingController();
    final repeat = TextEditingController();
    final encryption = TextEditingController();
    final key = GlobalKey<FormState>();
    bool register = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(register ? '注册安伴账号' : '登录安伴'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Form(
                key: key,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Note(
                      '资料和附件保存在云端，登录时自动读取。资料加密密码仅在当前会话使用；已有云端资料请填写原备份密码，遗失无法恢复。',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: username,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '账号（3–32 位字母、数字、下划线）',
                      ),
                      validator: (v) =>
                          RegExp(r'^[a-zA-Z0-9_]{3,32}$')
                              .hasMatch(v?.trim() ?? '')
                          ? null
                          : '账号格式不正确',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: secret,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '登录密码（至少 6 个字符）',
                      ),
                      validator: (v) {
                        final n = utf8.encode(v ?? '').length;
                        return (v?.runes.length ?? 0) >= 6 && n <= 72
                            ? null
                            : '密码至少 6 个字符，最多 72 字节';
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: encryption,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: '资料加密密码（至少 6 个字符）',
                      ),
                      validator: (v) => (v?.runes.length ?? 0) < 6
                          ? '请输入原备份密码；新账号请设置新密码'
                          : null,
                    ),
                    if (register) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: repeat,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(labelText: '确认密码'),
                        validator: (v) => v == secret.text ? null : '两次密码不一致',
                      ),
                    ],
                    TextButton(
                      onPressed: () => update(() => register = !register),
                      child: Text(register ? '已有账号？登录' : '没有账号？注册'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: Text(register ? '注册并登录' : '登录'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      await Account.login(
        widget.store,
        Account.apiBase,
        username.text.trim(),
        secret.text,
        register,
        encryption.text,
      );
      if (mounted) toast(context, '已登录 ${Account.current!['username']}');
    }
  }

  Future<void> migrate(bool offline) async {
    final old = await LocalVault.open(scope: offline ? '' : Account.scope);
    try {
      final oldData = await old.load();
      if (oldData.records.isEmpty && oldData.profile.isEmpty) {
        if (mounted) toast(context, '没有发现旧版本机资料');
        return;
      }
      if (!mounted ||
          !await confirm(
            context,
            '迁移旧版资料到当前账号？',
            '将上传 ${oldData.records.length} 条记录及其附件，并替换当前账号云端资料。上传成功后清除这份旧版本机资料；失败时原资料保留。',
            action: '上传并迁移',
          )) {
        return;
      }
      await widget.store.restore(await old.backup(oldData));
      await old.clear();
      if (mounted) toast(context, '已上传云端并清除旧版本机资料');
    } finally {
      await old.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loginOnly) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.spa_outlined, size: 48, color: pine),
            const SizedBox(height: 24),
            const Text('安伴 · 云端照护空间', style: TextStyle(fontSize: 26)),
            const SizedBox(height: 16),
            const Text('登录后读取云端资料，记录自动保存。', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (busy)
              const LinearProgressIndicator()
            else
              FilledButton(
                onPressed: () => run(connect),
                child: const Text('登录 / 注册'),
              ),
          ],
        ),
      );
    }
    final data = widget.store.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading('MY SPACE', '我的', '档案、隐私与提醒偏好。'),
        if (busy) const LinearProgressIndicator(),
        Section(
          '患者基础档案',
          trailing: TextButton(
            onPressed: busy ? null : () => run(editProfile),
            child: const Text('编辑'),
          ),
          child: Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.profile['name']?.isNotEmpty == true
                      ? data.profile['name']!
                      : '还未填写患者档案',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  '年龄：${data.profile['age'] ?? '未填写'}  ·  主治医生：${data.profile['doctor'] ?? '未填写'}',
                ),
                Text(data.profile['hospital'] ?? ''),
                Text(data.profile['note'] ?? ''),
              ],
            ),
          ),
        ),
        Section(
          '数据与隐私',
          child: Column(
            children: [
              option(
                Icons.lock_outline,
                '导出加密备份',
                '包含云端记录与附件',
                () => run(backup),
              ),
              option(
                Icons.restore,
                '从加密备份恢复',
                '完整校验后上传至当前账号',
                () => run(restore),
              ),
              option(
                Icons.refresh,
                '刷新云端资料',
                '读取当前账号最新数据',
                () => run(() => Account.refresh(widget.store)),
              ),
              option(
                Icons.move_up,
                '迁移旧版本机资料',
                '上传成功后清除对应本机资料',
                () => run(() => migrate(false)),
              ),
              option(
                Icons.move_up,
                '迁移旧版离线资料',
                '上传到当前账号并替换云端快照',
                () => run(() => migrate(true)),
              ),
              option(
                Icons.delete_outline,
                '清空云端资料',
                '清空当前账号记录与附件引用',
                () => run(() async {
                  if (!await confirm(
                    context,
                    '清空云端资料？',
                    '所有记录和行程将被清空，请先导出备份。',
                    action: '清空',
                  )) {
                    return;
                  }
                  await widget.store.clear();
                  await widget.reminders.refresh(
                    widget.store.data,
                    force: true,
                  );
                }),
              ),
              option(
                Icons.logout,
                '退出登录',
                Account.current?['username'] ?? '',
                () => run(() async {
                  await Account.logout(widget.store);
                  await widget.reminders.refresh(
                    widget.store.data,
                    force: true,
                  );
                }),
              ),
            ],
          ),
        ),
        Section(
          '使用偏好',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('大字模式'),
                value: data.settings['largeText'] == 'true',
                onChanged: busy
                    ? null
                    : (v) =>
                          run(() => widget.store.settings({'largeText': '$v'})),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('夜间模式'),
                value: data.settings['dark'] == 'true',
                onChanged: busy
                    ? null
                    : (v) => run(() => widget.store.settings({'dark': '$v'})),
              ),
              option(
                Icons.notifications_outlined,
                '设置',
                '用餐、喝水、PICC、输液港、化疗通知',
                () => openSettings(context, widget.store, widget.reminders),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget option(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback action,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 6),
    leading: Icon(icon, color: pine),
    title: Text(title),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, height: 1.7)),
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: busy ? null : action,
  );
}
