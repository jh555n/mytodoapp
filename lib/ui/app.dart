import 'dart:async';
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import '../services/icloud_calendar.dart';
import 'todo_editor.dart';

class DayweaveApp extends StatelessWidget {
  const DayweaveApp({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Dayweave',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        themeMode: ThemeMode.system,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: HomeScreen(controller: controller),
      );
  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF5B5BD6), brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF7F7FB)
          : const Color(0xFF171722),
      appBarTheme:
          const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none)),
      cardTheme: CardThemeData(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen(
      {super.key, required this.controller, this.handleDeepLinks = true});
  final AppController controller;
  final bool handleDeepLinks;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  AppController get c => widget.controller;
  int page = 0;
  DateTime selected = dateOnly(DateTime.now());
  bool weekView = false;
  bool showCompleted = false;
  String? categoryId;
  String search = '';
  StreamSubscription<Uri>? _links;
  final _appLinks = AppLinks();
  bool _editorOpen = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.handleDeepLinks) {
      _links = _appLinks.uriLinkStream.listen((uri) {
        if (uri.scheme == 'dayweave' && uri.host == 'add' && mounted) {
          _edit(initialDate: DateTime.now());
        }
      });
      _appLinks.getInitialLink().then((uri) {
        if (uri?.scheme == 'dayweave' && uri?.host == 'add' && mounted) {
          _edit(initialDate: DateTime.now());
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => c.sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      c.scheduleReminders();
      c.sync();
      setState(() {
        selected = dateOnly(selected);
      });
    }
  }

  @override
  void dispose() {
    _links?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _edit({Todo? todo, DateTime? initialDate}) async {
    if (_editorOpen) return;
    _editorOpen = true;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => TodoEditor(
            controller: c, existing: todo, initialDate: initialDate));
    _editorOpen = false;
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(c.errorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 800;
        final destinations = const [
          NavigationDestination(
              icon: Icon(Icons.check_circle_outline),
              selectedIcon: Icon(Icons.check_circle),
              label: '오늘'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: '캘린더'),
          NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: '카테고리'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: '설정'),
        ];
        return Scaffold(
          appBar: AppBar(
              title: const Row(children: [
                Icon(Icons.blur_on_rounded),
                SizedBox(width: 8),
                Text('dayweave',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, letterSpacing: -1))
              ]),
              actions: [
                if (c.syncing)
                  const Padding(
                      padding: EdgeInsets.all(18),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                else if (c.accounts.isNotEmpty)
                  IconButton(
                      onPressed: () => c.sync(),
                      icon: const Icon(Icons.sync),
                      tooltip: '캘린더 동기화'),
                const SizedBox(width: 8),
              ]),
          body: Row(children: [
            if (wide)
              NavigationRail(
                  selectedIndex: page,
                  onDestinationSelected: (index) =>
                      setState(() => page = index),
                  labelType: NavigationRailLabelType.all,
                  destinations: destinations
                      .map((d) => NavigationRailDestination(
                          icon: d.icon,
                          selectedIcon: d.selectedIcon,
                          label: Text(d.label)))
                      .toList()),
            Expanded(
                child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 850),
                        child: Column(children: [
                          if (c.warning != null)
                            MaterialBanner(
                                content: Text(c.warning!),
                                leading: const Icon(Icons.info_outline),
                                actions: [
                                  TextButton(
                                      onPressed: () {
                                        c.warning = null;
                                        setState(() {});
                                      },
                                      child: const Text('닫기'))
                                ]),
                          Expanded(child: _pageContent()),
                        ])))),
          ]),
          floatingActionButton: page < 2
              ? FloatingActionButton.extended(
                  onPressed: () =>
                      _edit(initialDate: page == 1 ? selected : null),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('할 일 추가'))
              : null,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: page,
                  onDestinationSelected: (index) =>
                      setState(() => page = index),
                  destinations: destinations),
        );
      });

  Widget _pageContent() {
    switch (page) {
      case 0:
        return _today();
      case 1:
        return _calendar();
      case 2:
        return _categories();
      default:
        return _settings();
    }
  }

  Widget _heading(String title, String subtitle, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 22),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ])),
        if (trailing != null) trailing,
      ]));
  Widget _filters() => Column(children: [
        TextField(
            onChanged: (value) => setState(() => search = value),
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '할 일과 메모 검색',
                isDense: true)),
        const SizedBox(height: 12),
        SizedBox(
            height: 42,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: const Text('전체'),
                      selected: categoryId == null,
                      onSelected: (_) => setState(() => categoryId = null))),
              ...c.categories.map((category) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      avatar: Icon(categoryIcons[category.icon],
                          size: 16, color: category.color),
                      label: Text(category.name),
                      selected: categoryId == category.id,
                      onSelected: (_) =>
                          setState(() => categoryId = category.id)))),
            ])),
      ]);
  Widget _empty(String message) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(children: [
        Icon(Icons.wb_sunny_outlined,
            size: 44, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text('작은 한 가지부터 시작해 보세요.', style: TextStyle(color: Colors.grey)),
      ]));

  Widget _today() {
    final now = dateOnly(DateTime.now());
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final today = c.occurrences(now, tomorrow,
        categoryId: categoryId, search: search, showCompleted: showCompleted);
    final undated = c
        .occurrences(now, tomorrow,
            includeUndated: true,
            categoryId: categoryId,
            search: search,
            showCompleted: showCompleted)
        .where((o) => o.at == null)
        .toList();
    final overdue = c.todos
        .where((t) =>
            !t.deleted &&
            !t.completed &&
            t.repeat.unit == RepeatUnit.none &&
            t.startsAt != null &&
            t.startsAt!.isBefore(now) &&
            (categoryId == null || t.categoryId == categoryId) &&
            '${t.title} ${t.notes}'
                .toLowerCase()
                .contains(search.toLowerCase()))
        .map((t) => TodoOccurrence(
            t, t.anchorAt ?? t.startsAt, t.startsAt, t.completed))
        .toList();
    final upcoming = c.occurrences(
        tomorrow, DateTime(now.year, now.month, now.day + 8),
        categoryId: categoryId, search: search, showCompleted: showCompleted);
    return ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 110),
        children: [
          _heading('오늘을 가볍게', DateFormat('M월 d일 EEEE', 'ko').format(now),
              trailing: IconButton(
                  onPressed: () =>
                      setState(() => showCompleted = !showCompleted),
                  icon: Icon(showCompleted
                      ? Icons.visibility
                      : Icons.visibility_off_outlined),
                  tooltip: '완료 항목 표시')),
          _filters(),
          const SizedBox(height: 24),
          if (overdue.isNotEmpty) ...[
            _section('기한이 지난 할 일', overdue.length),
            ...overdue.map(_tile)
          ],
          _section('오늘', today.length),
          if (today.isEmpty)
            _empty('오늘 예정된 할 일이 없어요.')
          else
            ...today.map(_tile),
          if (undated.isNotEmpty) ...[
            _section('수집함', undated.length),
            ...undated.map(_tile)
          ],
          if (upcoming.isNotEmpty) ...[
            _section('다음 7일', upcoming.length),
            ...upcoming.map(_tile)
          ],
          if (c.todos.any((t) => t.repeat.shift != HolidayShift.keep))
            const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Text(
                    '공휴일 자동 이동은 현재 한국 2026년 데이터로 계산합니다.\n다른 연도는 공휴일 데이터를 추가해야 합니다.',
                    style: TextStyle(fontSize: 12, color: Colors.grey))),
        ]);
  }

  Widget _section(String title, int count) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 14),
      child: Row(children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text('$count', style: const TextStyle(color: Colors.grey))
      ]));
  Widget _tile(TodoOccurrence item) {
    final category = c.category(item.todo.categoryId);
    return Card(
        child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _edit(todo: item.todo),
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                child: Row(children: [
                  item.todo.readOnly
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.event_outlined))
                      : Checkbox(
                          value: item.completed,
                          onChanged: (_) => _perform(() => c.toggle(item))),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(item.todo.title,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                decoration: item.completed
                                    ? TextDecoration.lineThrough
                                    : null)),
                        const SizedBox(height: 5),
                        Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (category != null)
                                Text('● ${category.name}',
                                    style: TextStyle(
                                        color: category.color, fontSize: 12)),
                              if (item.at != null)
                                Text(
                                    DateFormat(item.todo.allDay
                                            ? 'M/d'
                                            : 'M/d HH:mm')
                                        .format(item.at!),
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                              if (item.todo.repeat.unit != RepeatUnit.none)
                                const Icon(Icons.repeat,
                                    size: 14, color: Colors.grey),
                              if (item.todo.reminderMinutes != null)
                                const Icon(Icons.notifications_none,
                                    size: 14, color: Colors.grey),
                              if (item.todo.dirty)
                                const Text('동기화 대기',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.orange)),
                              if (item.todo.readOnly)
                                const Text('외부 일정',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                              if (item.todo.steps.isNotEmpty)
                                Text(
                                    '${item.todo.steps.where((step) => step.completed).length}/${item.todo.steps.length}',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                            ]),
                      ])),
                  if (item.todo.priority > 0)
                    Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(Icons.flag_outlined,
                            size: 19,
                            color: item.todo.priority == 2
                                ? Colors.redAccent
                                : Colors.orange)),
                ]))));
  }

  Widget _calendar() {
    final monthStart = DateTime(selected.year, selected.month);
    final first = weekView
        ? DateTime(
            selected.year, selected.month, selected.day - selected.weekday + 1)
        : DateTime(monthStart.year, monthStart.month, 2 - monthStart.weekday);
    final days = weekView ? 7 : 42;
    final until = DateTime(first.year, first.month, first.day + days);
    final events = c.occurrences(first, until,
        categoryId: categoryId, search: search, showCompleted: showCompleted);
    final byDay = <String, List<TodoOccurrence>>{};
    for (final event in events) {
      byDay.putIfAbsent(dayKey(event.at!), () => []).add(event);
    }
    final chosen = byDay[dayKey(selected)] ?? [];
    final holiday = c.engine.holidays.holidays[dayKey(selected)];
    final now = dateOnly(DateTime.now());
    return ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 110),
        children: [
          _heading('나의 캘린더', '일정 사이에, 나를 위한 시간',
              trailing: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('주')),
                    ButtonSegment(value: false, label: Text('월'))
                  ],
                  selected: {weekView},
                  onSelectionChanged: (value) =>
                      setState(() => weekView = value.first))),
          _filters(),
          const SizedBox(height: 20),
          Row(children: [
            Text(DateFormat('yyyy년 M월', 'ko').format(selected),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
                onPressed: () => setState(() => selected = weekView
                    ? DateTime(selected.year, selected.month, selected.day - 7)
                    : DateTime(selected.year, selected.month - 1)),
                icon: const Icon(Icons.chevron_left)),
            TextButton(
                onPressed: () => setState(() => selected = now),
                child: const Text('오늘')),
            IconButton(
                onPressed: () => setState(() => selected = weekView
                    ? DateTime(selected.year, selected.month, selected.day + 7)
                    : DateTime(selected.year, selected.month + 1)),
                icon: const Icon(Icons.chevron_right)),
          ]),
          const SizedBox(height: 10),
          Row(
              children: ['월', '화', '수', '목', '금', '토', '일']
                  .map((name) => Expanded(
                      child: Center(
                          child: Text(name,
                              style: const TextStyle(color: Colors.grey)))))
                  .toList()),
          const SizedBox(height: 10),
          GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: days,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: weekView ? 92 : 65,
                  crossAxisSpacing: 3,
                  mainAxisSpacing: 4),
              itemBuilder: (context, index) {
                final day =
                    DateTime(first.year, first.month, first.day + index);
                final active = day == selected;
                final daily = byDay[dayKey(day)] ?? [];
                final isHoliday =
                    c.engine.holidays.holidays.containsKey(dayKey(day));
                return Semantics(
                    label: '${day.month}월 ${day.day}일, 일정 ${daily.length}개',
                    selected: active,
                    child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => selected = day),
                        onLongPress: () => _edit(initialDate: day),
                        child: Container(
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: active
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                    : null,
                                border: day == now
                                    ? Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary)
                                    : null),
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('${day.day}',
                                      style: TextStyle(
                                          fontWeight: active
                                              ? FontWeight.w800
                                              : FontWeight.w500,
                                          color: !weekView &&
                                                  day.month != selected.month
                                              ? Colors.grey
                                              : day.weekday ==
                                                          DateTime.sunday ||
                                                      isHoliday
                                                  ? Colors.redAccent
                                                  : null)),
                                  const SizedBox(height: 7),
                                  Wrap(
                                      spacing: 3,
                                      children: daily
                                          .take(3)
                                          .map((event) => Container(
                                              width: 5,
                                              height: 5,
                                              decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: c
                                                          .category(event
                                                              .todo.categoryId)
                                                          ?.color ??
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .primary)))
                                          .toList()),
                                  if (daily.length > 3)
                                    Text('+${daily.length - 3}',
                                        style: const TextStyle(fontSize: 9)),
                                ]))));
              }),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(
                child: Text(DateFormat('M월 d일 EEEE', 'ko').format(selected),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 17))),
            IconButton(
                onPressed: () => _edit(initialDate: selected),
                icon: const Icon(Icons.add_circle_outline),
                tooltip: '선택한 날짜에 추가')
          ]),
          if (holiday != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(holiday,
                    style: const TextStyle(color: Colors.redAccent))),
          if (chosen.isEmpty)
            _empty('선택한 날짜에 일정이 없어요.')
          else
            ...chosen.map(_tile),
        ]);
  }

  Widget _categories() =>
      ListView(padding: const EdgeInsets.fromLTRB(24, 12, 24, 32), children: [
        _heading('나만의 카테고리', '색상과 아이콘으로 하루를 구분하세요',
            trailing: IconButton(
                onPressed: () => _categoryEditor(),
                icon: const Icon(Icons.add_circle_outline),
                tooltip: '카테고리 추가')),
        ...c.categories.map((category) => Card(
            child: ListTile(
                leading: CircleAvatar(
                    backgroundColor: category.color.withValues(alpha: .12),
                    child: Icon(categoryIcons[category.icon],
                        color: category.color)),
                title: Text(category.name),
                subtitle: Text(
                    category.remoteKey == null ? '기기 내 카테고리' : '캘린더에서 자동 연동'),
                trailing: category.remoteKey == null
                    ? const Icon(Icons.edit_outlined, size: 19)
                    : const Icon(Icons.sync, size: 19),
                onTap: category.remoteKey == null
                    ? () => _categoryEditor(category)
                    : null))),
      ]);
  Future<void> _categoryEditor([TodoCategory? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    var color = existing?.colorValue ?? categoryColors.first;
    var icon = existing?.icon ?? 'work';
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: Text(existing == null ? '카테고리 추가' : '카테고리 수정'),
                    content: SizedBox(
                        width: 320,
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                  controller: name,
                                  maxLength: 40,
                                  decoration:
                                      const InputDecoration(labelText: '이름')),
                              const SizedBox(height: 18),
                              Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: categoryColors
                                      .map((value) => InkWell(
                                          onTap: () =>
                                              update(() => color = value),
                                          child: CircleAvatar(
                                              radius: 17,
                                              backgroundColor: Color(value),
                                              child: color == value
                                                  ? const Icon(Icons.check,
                                                      color: Colors.white,
                                                      size: 20)
                                                  : null)))
                                      .toList()),
                              const SizedBox(height: 18),
                              Wrap(
                                  spacing: 4,
                                  children: categoryIcons.entries
                                      .map((entry) => IconButton(
                                          onPressed: () =>
                                              update(() => icon = entry.key),
                                          icon: Icon(entry.value),
                                          color: icon == entry.key
                                              ? Color(color)
                                              : Colors.grey))
                                      .toList()),
                            ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('취소')),
                      FilledButton(
                          onPressed: () async {
                            try {
                              await c.saveCategory(name.text, color, icon,
                                  existing: existing);
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                    SnackBar(content: Text(c.errorMessage(e))));
                              }
                            }
                          },
                          child: const Text('저장'))
                    ])));
    name.dispose();
  }

  Widget _settings() =>
      ListView(padding: const EdgeInsets.fromLTRB(24, 12, 24, 32), children: [
        _heading('설정', '내 데이터, 내 방식으로'),
        Card(
            child: const ListTile(
                leading: Icon(Icons.phone_iphone),
                title: Text('기기 내 저장이 기본입니다'),
                subtitle:
                    Text('연결하지 않은 할 일은 이 기기에만 보관됩니다. 앱 삭제 시 데이터가 사라집니다.'))),
        Card(
            child: SwitchListTile(
                title: const Text('할 일 알림'),
                subtitle: const Text('종일 할 일은 오전 9시 기준으로 알려드려요'),
                value: c.notificationsEnabled,
                onChanged: (enabled) =>
                    _perform(() => c.enableNotifications(enabled)))),
        const SizedBox(height: 20),
        _section('캘린더 연결', c.accounts.length),
        ...c.conflicts.entries.map((entry) => Card(
            child: ListTile(
                leading: const Icon(Icons.sync_problem, color: Colors.orange),
                title: Text(entry.value.local.title),
                subtitle: const Text('양쪽에서 수정된 일정 · 변경 내용 선택'),
                onTap: c.syncing ? null : () => _resolveConflict(entry.key)))),
        _connection(
            CalendarProvider.google, 'Google Calendar', Icons.event_note),
        if (Platform.isIOS)
          _connection(
              CalendarProvider.apple, 'Apple Calendar', Icons.calendar_month),
        _connection(CalendarProvider.icloud, 'iCloud Calendar · CalDAV',
            Icons.cloud_outlined),
        const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 20),
            child: Text(
                'iCloud 직접 연결은 Apple ID의 앱 전용 암호가 필요합니다.\n'
                'iOS에서는 Apple Calendar 연결을 권장합니다. 같은 캘린더를 두 방식으로 연결하면 중복 표시될 수 있습니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey))),
        Card(
            child: const ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('빠른 등록'),
                subtitle: Text(
                    '지원 기기에서 Dayweave 위젯을 추가하세요. 누르면 잠금 해제 후 등록 화면이 열립니다.'))),
        Card(
            child: const ListTile(
                leading: Icon(Icons.event_repeat),
                title: Text('공휴일 데이터'),
                subtitle: Text(
                    '한국 2026년 공휴일 · 주말 포함 여부는 반복 할 일마다 선택합니다. 다른 연도는 데이터 추가가 필요합니다.'))),
        const SizedBox(height: 18),
        const Center(
            child: Text('Dayweave 0.1.0 · 내 하루를 가볍게',
                style: TextStyle(color: Colors.grey, fontSize: 12))),
      ]);
  Future<void> _resolveConflict(String id) async {
    final pair = c.conflicts[id];
    if (pair == null) return;
    final choice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('어떤 변경을 유지할까요?'),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('이 기기',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                          '${pair.local.deleted ? '삭제 예정' : pair.local.title}\n${pair.local.startsAt ?? '날짜 없음'}\n${pair.local.notes}'),
                      const SizedBox(height: 16),
                      const Text('외부 캘린더',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                          '${pair.remote.title}\n${pair.remote.startsAt ?? '날짜 없음'}\n${pair.remote.notes}'),
                    ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('나중에')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('외부 변경 유지')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('기기 변경 반영'))
                ]));
    if (choice != null) {
      await _perform(() => c.resolveConflict(id, keepLocal: choice));
    }
  }

  Widget _connection(CalendarProvider provider, String name, IconData icon) {
    final account = c.accounts[provider];
    final calendars = c.remoteCalendars[provider] ?? [];
    return Card(
        child: Column(children: [
      ListTile(
          leading: Icon(icon),
          title: Text(name),
          subtitle: Text(account?.displayName ?? '연결 안 됨'),
          trailing: account == null
              ? TextButton(
                  onPressed: c.syncing
                      ? null
                      : () => _perform(() async {
                            if (provider == CalendarProvider.icloud &&
                                !(await _iCloudCredentials())) {
                              return;
                            }
                            await c.connect(provider);
                          }),
                  child: const Text('연결'))
              : TextButton(
                  onPressed: c.syncing ? null : () => _disconnect(provider),
                  child: const Text('해제'))),
      if (account != null) ...[
        const Divider(height: 1),
        if (calendars.isEmpty)
          ListTile(
              title: const Text('캘린더 목록 가져오기'),
              trailing: const Icon(Icons.refresh),
              onTap: () => c.sync()),
        ...calendars.map((calendar) => CheckboxListTile(
            dense: true,
            title: Text(calendar.name),
            subtitle: calendar.writable ? null : const Text('읽기 전용'),
            secondary:
                Icon(Icons.circle, size: 15, color: Color(calendar.color)),
            value:
                c.selectedCalendars[provider]?.contains(calendar.id) ?? false,
            onChanged: c.syncing
                ? null
                : (selected) => _perform(() => c.selectCalendar(
                    provider, calendar.id, selected ?? false)))),
      ],
    ]));
  }

  Future<bool> _iCloudCredentials() async {
    final email = TextEditingController();
    final password = TextEditingController();
    final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('iCloud 캘린더 연결'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Apple 계정에서 발급한 앱 전용 암호를 입력하세요. 일반 로그인 암호는 사용하지 마세요.'),
                  const SizedBox(height: 16),
                  TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration:
                          const InputDecoration(labelText: 'Apple ID 이메일')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: password,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(labelText: '앱 전용 암호')),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소')),
                  FilledButton(
                      onPressed: () => Navigator.pop(
                          context,
                          email.text.trim().isNotEmpty &&
                              password.text.trim().isNotEmpty),
                      child: const Text('연결'))
                ]));
    if (result == true) {
      final connector =
          c.connectors[CalendarProvider.icloud]! as ICloudCalendarConnector;
      connector.email = email.text.trim();
      connector.password = password.text.trim();
    }
    email.dispose();
    password.dispose();
    return result ?? false;
  }

  Future<void> _disconnect(CalendarProvider provider) async {
    final choice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('캘린더 연결 해제'),
                content: const Text('외부 캘린더의 일정은 유지됩니다. 가져온 데이터를 이 기기에 남길까요?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('기기에서 제거')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('기기에 남기기'))
                ]));
    if (choice != null) {
      await _perform(() => c.disconnect(provider, keepImported: choice));
    }
  }
}
