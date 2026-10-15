import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../data/vault.dart';
import '../services/reminders.dart';

import '../services/account.dart';
import '../services/app_update.dart';
import '../ui.dart';
import 'settings.dart';

class ProfilePage extends StatefulWidget {
  final CareStore store;
  final ReminderService reminders;
  final bool loginOnly;
  final String? restoreError;
  const ProfilePage({
    super.key,
    required this.store,
    required this.reminders,
    this.loginOnly = false,
    this.restoreError,
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
      'name': '称呼',
      'age': '年龄',
      'diagnosis': '确诊日期',
      'doctor': '主治医生',
      'hospital': '常用医院',
      'note': '基础备注',
    };
    final controllers = {
      for (final k in names.keys)
        k: TextEditingController(text: widget.store.data.profile[k] ?? ''),
    };
    final key = GlobalKey<FormState>();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('个人档案'),
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
        title: const Text('输入旧版备份密码'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '该文件属于旧版加密备份，需要原密码解密。',
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
    final backup = await widget.store.vault.backup(widget.store.data);
    final envelope = await sealBackup(backup);
    final path = await FilePicker.saveFile(
      fileName: '安伴-${dayKey(DateTime.now())}.anban',
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
    );
    if (mounted) {
      toast(context, path == null ? '已关闭保存窗口；请确认下载或保存结果' : '资料备份已导出');
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
    final raw = Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
    Map<String, dynamic> backup;
    if (raw.containsKey('ciphertext') || raw['version'] == 1) {
      final secret = await password();
      if (secret == null) {
        return;
      }
      backup = await openBackup(raw, secret);
    } else {
      backup = await openBackup(raw);
    }
    final restored = CareData.fromJson(backup['data']);
    if (!mounted ||
        !await confirm(
          context,
          '恢复 ${restored.records.length} 条记录？',
          '将上传并替换当前账号云端资料与附件。建议先导出当前资料备份。文件错误时不会覆盖现有数据。',
          action: '替换并恢复',
        )) {
      return;
    }
    await widget.store.restore(backup);
    if (mounted) {
      toast(context, '资料备份已恢复');
    }
  }

  Future<void> connect() async {
    final username = TextEditingController();
    final secret = TextEditingController();
    final repeat = TextEditingController();
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
                      '登录后自动同步云端资料与附件，此设备会保持登录状态。',
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
      try {
        await Account.login(
          widget.store,
          Account.apiBase,
          username.text.trim(),
          secret.text,
          register,
        );
        if (mounted) toast(context, '已登录 ${Account.current!['username']}');
      } catch (e) {
        final err = e.toString();
        if (err.contains('加密备份') ||
            err.contains('SecretBox') ||
            err.contains('解密密码')) {
          if (!mounted) rethrow;
          final migrationPassword = await _promptLegacyDecryptionPassword(context);
          if (migrationPassword != null && migrationPassword.isNotEmpty) {
            await Account.login(
              widget.store,
              Account.apiBase,
              username.text.trim(),
              secret.text,
              false,
              migrationPassword,
            );
            if (mounted) toast(context, '已登录并完成历史数据平滑迁移');
            return;
          }
        }
        rethrow;
      }
    }
  }

  Future<String?> _promptLegacyDecryptionPassword(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入旧版数据解密密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '检测到您的云端包含旧版加密备份，且与登录密码不一致。请输入历史解密密码以导入并永久转换为新版免密格式：',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '旧版数据解密密码',
                hintText: '输入历史设置的独立加密密码',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确认迁移并登录'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeroCard(CareData data) {
    final profile = data.profile;
    final name = profile['name']?.trim().isNotEmpty == true ? profile['name']! : '未填写称呼';
    final age = profile['age']?.trim().isNotEmpty == true ? '${profile['age']} 岁' : '年龄待补充';
    final doctor = profile['doctor']?.trim().isNotEmpty == true ? profile['doctor']! : '医生待补充';
    final hospital = profile['hospital']?.trim().isNotEmpty == true ? profile['hospital']! : '医院待补充';
    final diagnosis = profile['diagnosis']?.trim().isNotEmpty == true ? profile['diagnosis']! : '';
    final note = profile['note']?.trim() ?? '';

    // 计算陪伴守护天数
    int days = 1;
    if (diagnosis.isNotEmpty) {
      final diagDate = DateTime.tryParse(diagnosis);
      if (diagDate != null) {
        days = DateTime.now().difference(diagDate).inDays.abs() + 1;
      }
    } else if (data.records.isNotEmpty) {
      days = DateTime.now().difference(data.records.last.at).inDays.abs() + 1;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF245B4B), Color(0xFF1B4539)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x28245B4B),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 背景微装饰
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部姓名与编辑入口
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        name.characters.first,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  age,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            diagnosis.isNotEmpty ? '确诊日期：$diagnosis' : '完善个人档案，记录日常点滴',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => run(editProfile),
                      icon: const Icon(Icons.edit_outlined, size: 14, color: Colors.white),
                      label: const Text('编辑', style: TextStyle(color: Colors.white, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // 医院与主治医师
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.local_hospital_rounded, size: 16, color: Color(0xFFB4E3D5)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$hospital · $doctor',
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                if (note.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '备注：$note',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 18),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 16),

                // 三列数据里程碑统计
                Row(
                  children: [
                    Expanded(child: _buildMilestoneColumn('安全守护', '$days', '天')),
                    Container(height: 24, width: 1, color: Colors.white24),
                    Expanded(child: _buildMilestoneColumn('健康记录', '${data.records.length}', '条')),
                    Container(height: 24, width: 1, color: Colors.white24),
                    Expanded(child: _buildMilestoneColumn('数据安全', '端到端', '加密')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMilestoneColumn(String label, String value, String unit) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unit,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: pine.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: pine, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: pine,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11.5, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback action,
    bool isDestructive = false,
  }) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 4),
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDestructive
            ? danger.withValues(alpha: 0.1)
            : pine.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        color: isDestructive ? danger : pine,
        size: 20,
      ),
    ),
    title: Text(
      title,
      style: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        color: isDestructive ? danger : null,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: const TextStyle(fontSize: 12, color: muted, height: 1.5),
    ),
    trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: muted),
    onTap: busy ? null : action,
  );

  @override
  Widget build(BuildContext context) {
    if (widget.loginOnly) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Surface(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: pine.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.spa_rounded, size: 48, color: pine),
                ),
                const SizedBox(height: 20),
                const Text(
                  '安伴 · 云端照护空间',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: pine,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '登录后读取加密云端资料，健康与用药记录全自动安全同步。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 13.5, height: 1.6),
                ),
                if (widget.restoreError != null) ...[
                  const SizedBox(height: 16),
                  Note(widget.restoreError!, urgent: true),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            if (!await Account.restore(widget.store) &&
                                context.mounted) {
                              toast(context, '登录已过期，请重新登录；此设备已记住的资料密码可留空');
                            }
                          }),
                    child: const Text('重试自动登录'),
                  ),
                ],
                const SizedBox(height: 24),
                if (busy)
                  const LinearProgressIndicator()
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => run(connect),
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('登录 / 注册'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                if (AppUpdate.supported) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => run(() => AppUpdate.check(context)),
                    icon: const Icon(Icons.system_update_outlined, size: 16),
                    label: const Text('检查最新版本', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final data = widget.store.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading('MY SPACE', '我的', '档案、隐私与提醒偏好。'),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: LinearProgressIndicator(),
          ),

        // 1. 个人档案名片 Hero Card
        _buildProfileHeroCard(data),

        // 2. 数据与隐私安全卡片
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                icon: Icons.shield_outlined,
                title: '数据与隐私安全',
                subtitle: '端到端高强度加密，数据自主掌控',
              ),
              _buildModernOption(
                icon: Icons.file_download_outlined,
                title: '导出加密备份',
                subtitle: '包含云端记录与附件，生成安全 .anban 文件',
                action: () => run(backup),
              ),
              const Divider(height: 1),
              _buildModernOption(
                icon: Icons.settings_backup_restore_rounded,
                title: '从加密备份恢复',
                subtitle: '密码校验后安全覆盖还原资料',
                action: () => run(restore),
              ),
              const Divider(height: 1),
              _buildModernOption(
                icon: Icons.logout_rounded,
                title: '退出登录',
                subtitle: '当前账号：${Account.current?['username'] ?? '未登录'}',
                action: () => run(() async {
                  await Account.logout(widget.store);
                  await widget.reminders.refresh(
                    widget.store.data,
                    force: true,
                    clearTest: true,
                  );
                }),
                isDestructive: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 3. 照护使用偏好
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                icon: Icons.tune_rounded,
                title: '界面与使用偏好',
                subtitle: '关怀老年阅读、舒缓暗色体验',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: pine.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.text_fields_rounded, color: pine, size: 20),
                ),
                title: const Text('大字关怀模式', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('放大核心文字与排版，方便长辈阅读', style: TextStyle(fontSize: 12)),
                value: data.settings['largeText'] == 'true',
                onChanged: busy
                    ? null
                    : (v) => run(() => widget.store.settings({'largeText': '$v'})),
              ),
              const Divider(height: 1),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: pine.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.dark_mode_outlined, color: pine, size: 20),
                ),
                title: const Text('夜间深色模式', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('减少夜间屏幕强光刺激，安心休养', style: TextStyle(fontSize: 12)),
                value: data.settings['dark'] == 'true',
                onChanged: busy
                    ? null
                    : (v) => run(() => widget.store.settings({'dark': '$v'})),
              ),
              const Divider(height: 1),
              _buildModernOption(
                icon: Icons.alarm_on_rounded,
                title: '提醒与推送细项设置',
                subtitle: '用餐、喝水、PICC、输液港、化疗周期排程与桌面卡片',
                action: () => openSettings(context, widget.store, widget.reminders),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 4. 版本与应用支持
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                icon: Icons.info_outline_rounded,
                title: '关于安伴',
                subtitle: '安心记录日常，温暖陪伴家人',
              ),
              if (AppUpdate.supported) ...[
                _buildModernOption(
                  icon: Icons.system_update_rounded,
                  title: '检查应用更新',
                  subtitle: '获取最新的功能与安全修复',
                  action: () => run(() => AppUpdate.check(context)),
                ),
                const Divider(height: 1),
                FutureBuilder<String?>(
                  future: AppUpdate.installedVersionName(),
                  builder: (_, snapshot) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: pine.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.check_circle_outline_rounded, color: pine, size: 20),
                    ),
                    title: const Text('当前版本号', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                    trailing: Text(
                      snapshot.data ?? '读取中…',
                      style: const TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
