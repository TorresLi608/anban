import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/store.dart';
import 'data/vault.dart';
import 'services/media_source.dart';
import 'services/account.dart';
import 'services/reminders.dart';
import 'screens/home.dart';
import 'screens/records.dart';
import 'screens/care.dart';
import 'screens/profile.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await purgeMediaPreviews();
    final vault = await LocalVault.memory();
    final store = CareStore(vault, await vault.load());
    store.publish = (_, _) async => throw StateError('请先登录');
    final reminders = ReminderService();
    await reminders.initialize();
    await reminders.refresh(store.data, force: true);
    runApp(AnbanApp(store: store, reminders: reminders, requireLogin: true));
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 48),
                    const SizedBox(height: 24),
                    const Text('无法启动云端照护空间', style: TextStyle(fontSize: 24)),
                    const SizedBox(height: 16),
                    Text('$e', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    const Text(
                      '云端资料未被覆盖，请重启应用。浏览器请使用 localhost 或 HTTPS。',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AnbanApp extends StatelessWidget {
  final CareStore store;
  final ReminderService reminders;
  final bool requireLogin;
  const AnbanApp({
    super.key,
    required this.store,
    required this.reminders,
    this.requireLogin = true,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (_, _) => MaterialApp(
      title: '安伴 · 居家照护',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'NotoSansSC',
        scaffoldBackgroundColor: paper,
        colorScheme: ColorScheme.fromSeed(seedColor: pine, surface: paper),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            color: ink,
            letterSpacing: -.7,
          ),
          headlineSmall: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: ink,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
          bodyMedium: TextStyle(fontSize: 14, color: ink),
          bodyLarge: TextStyle(fontSize: 16, color: ink),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: paper,
          surfaceTintColor: Colors.transparent,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: pine,
            foregroundColor: Colors.white,
            minimumSize: const Size(44, 46),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: pine,
            minimumSize: const Size(44, 44),
            side: const BorderSide(color: line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: line),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white,
          selectedColor: const Color(0xFFDDE9DF),
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        dividerTheme: const DividerThemeData(color: line, thickness: 1),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(
            (MediaQuery.textScalerOf(context).scale(1) *
                    (store.data.settings['largeText'] == 'true' ? 1.25 : 1))
                .clamp(1, 2),
          ),
        ),
        child: child!,
      ),
      home: requireLogin && Account.current == null
          ? Scaffold(
              body: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ProfilePage(
                      store: store,
                      reminders: reminders,
                      loginOnly: true,
                    ),
                  ),
                ),
              ),
            )
          : CareShell(store: store, reminders: reminders),
    ),
  );
}

class CareShell extends StatefulWidget {
  final CareStore store;
  final ReminderService reminders;
  const CareShell({super.key, required this.store, required this.reminders});
  @override
  State<CareShell> createState() => _CareShellState();
}

class _CareShellState extends State<CareShell> with WidgetsBindingObserver {
  int selected = 0;
  Timer? timer;
  static const names = ['首页', '健康记录', '行程', '我的'];
  static const icons = [
    Icons.space_dashboard_outlined,
    Icons.edit_note_rounded,
    Icons.menu_book_outlined,
    Icons.person_outline_rounded,
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(changed);
    changed();
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
        widget.reminders.refresh(widget.store.data);
      }
    });
  }

  void changed() {
    widget.reminders.refresh(widget.store.data);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.reminders.refresh(widget.store.data, force: true);
      setState(() {});
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.store.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    Widget page = switch (selected) {
      0 => HomePage(
        store: widget.store,
        reminders: widget.reminders,
        navigate: (i) => setState(() => selected = i),
      ),
      1 => RecordsPage(store: widget.store),
      2 => CarePage(store: widget.store),
      _ => ProfilePage(store: widget.store, reminders: widget.reminders),
    };
    final scaffold = Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              Container(
                width: 216,
                decoration: const BoxDecoration(
                  color: Color(0xFFEEF0E9),
                  border: Border(right: BorderSide(color: line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(28, 34, 24, 42),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.spa_outlined, color: pine, size: 28),
                              SizedBox(width: 10),
                              Text(
                                '安伴',
                                style: TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.w600,
                                  color: pine,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Text(
                            '把陪护的事，安心记好',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ),
                    for (var i = 0; i < names.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            selected: i == selected,
                            selectedTileColor: const Color(0xFFDCE7DB),
                            selectedColor: pine,
                            leading: Icon(icons[i], size: 22),
                            title: Text(
                              names[i],
                              style: const TextStyle(fontSize: 14),
                            ),
                            onTap: () => setState(() => selected = i),
                          ),
                        ),
                      ),
                    const Spacer(),
                    const Padding(
                      padding: EdgeInsets.all(26),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline, size: 16, color: muted),
                          SizedBox(width: 8),
                          Text(
                            '云端加密保存',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 40 : 22,
                      18,
                      wide ? 40 : 22,
                      14,
                    ),
                    child: Row(
                      children: [
                        if (!wide) ...[
                          const Icon(Icons.spa_outlined, color: pine, size: 23),
                          const SizedBox(width: 8),
                          const Text(
                            '安伴',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: pine,
                            ),
                          ),
                        ] else
                          const Text(
                            '居家照护空间',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        const Spacer(),
                        const Icon(
                          Icons.verified_user_outlined,
                          size: 15,
                          color: pine,
                        ),
                        const SizedBox(width: 7),
                        const Text(
                          '云端保存',
                          style: TextStyle(color: pine, fontSize: 11),
                        ),
                        const SizedBox(width: 18),
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: const Color(0xFFE1E8DF),
                          child: Text(
                            widget.store.data.profile['name']?.isNotEmpty ==
                                    true
                                ? widget.store.data.profile['name']!.substring(
                                    0,
                                    1,
                                  )
                                : '家',
                            style: const TextStyle(color: pine, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: SingleChildScrollView(
                        key: ValueKey(selected),
                        padding: EdgeInsets.fromLTRB(
                          wide ? 40 : 22,
                          wide ? 36 : 26,
                          wide ? 40 : 22,
                          120,
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1160),
                            child: page,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              backgroundColor: const Color(0xFFF9FAF6),
              indicatorColor: const Color(0xFFDDE8DC),
              selectedIndex: selected,
              onDestinationSelected: (i) => setState(() => selected = i),
              destinations: [
                for (var i = 0; i < names.length; i++)
                  NavigationDestination(icon: Icon(icons[i]), label: names[i]),
              ],
            ),
    );
    // Reverse luminance while preserving hues. Media opens outside this filtered route.
    return widget.store.data.settings['dark'] == 'true'
        ? ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              .5748,
              -1.4304,
              -.1444,
              0,
              242,
              -.4252,
              -.4304,
              -.1444,
              0,
              242,
              -.4252,
              -1.4304,
              .8556,
              0,
              242,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: scaffold,
          )
        : scaffold;
  }
}
