import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_controller.dart';
import '../domain/models.dart';

class TodoEditor extends StatefulWidget {
  const TodoEditor(
      {super.key, required this.controller, this.existing, this.initialDate});
  final AppController controller;
  final Todo? existing;
  final DateTime? initialDate;
  @override
  State<TodoEditor> createState() => _TodoEditorState();
}

class _TodoEditorState extends State<TodoEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _notes;
  final _stepInput = TextEditingController();
  List<ChecklistStep> _steps = [];
  late DateTime? _date;
  late bool _allDay;
  String? _category;
  int _priority = 0;
  int? _reminder;
  RepeatUnit _unit = RepeatUnit.none;
  int _interval = 1;
  HolidayShift _shift = HolidayShift.keep;
  bool _weekends = true;
  CalendarProvider? _provider;
  String? _calendarId;
  bool _saving = false;
  String? _error;
  AppController get c => widget.controller;
  bool get readOnly => widget.existing?.readOnly ?? false;
  @override
  void initState() {
    super.initState();
    final todo = widget.existing;
    _title = TextEditingController(text: todo?.title ?? '');
    _notes = TextEditingController(text: todo?.notes ?? '');
    _steps = List.of(todo?.steps ?? []);
    _date = todo?.anchorAt ?? todo?.startsAt ?? widget.initialDate;
    _allDay = todo?.allDay ?? true;
    _category = todo?.categoryId;
    _priority = todo?.priority ?? 0;
    _reminder = todo?.reminderMinutes;
    _unit = todo?.repeat.unit ?? RepeatUnit.none;
    _interval = todo?.repeat.interval ?? 1;
    _shift = todo?.repeat.shift ?? HolidayShift.keep;
    _weekends = todo?.repeat.weekendsAreHolidays ?? true;
    _provider = todo?.provider;
    _calendarId = todo?.calendarId;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _stepInput.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
        context: context,
        initialDate: _date ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (date != null && mounted) {
      setState(() => _date = DateTime(date.year, date.month, date.day,
          _date?.hour ?? 9, _date?.minute ?? 0));
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_date ?? DateTime.now()));
    if (time != null && mounted) {
      final date = _date ?? DateTime.now();
      setState(() {
        _date =
            DateTime(date.year, date.month, date.day, time.hour, time.minute);
        _allDay = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_reminder != null && !c.notificationsEnabled) {
        await c.enableNotifications(true);
      }
      final date = _date == null
          ? null
          : _allDay
              ? dateOnly(_date!)
              : _date;
      await c.saveTodo(
          existing: widget.existing,
          title: _title.text,
          notes: _notes.text,
          categoryId: _category,
          anchor: date,
          allDay: _allDay,
          priority: _priority,
          reminderMinutes: _date == null ? null : _reminder,
          repeat: RepeatRule(
              unit: _unit,
              interval: _interval,
              shift: _shift,
              weekendsAreHolidays: _weekends),
          provider: _provider,
          calendarId: _calendarId,
          steps: _steps);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = c.errorMessage(error);
          _saving = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('할 일을 삭제할까요?'),
                content: Text(_unit == RepeatUnit.none
                    ? '연결된 앱 소유 일정도 삭제됩니다.'
                    : '반복 할 일 전체와 완료 기록이 삭제됩니다.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('삭제'))
                ]));
    if (confirmed != true) return;
    try {
      await c.delete(widget.existing!);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = c.errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final calendars = (c.remoteCalendars[_provider] ?? [])
        .where((calendar) =>
            calendar.writable &&
            (c.selectedCalendars[_provider]?.contains(calendar.id) ?? false))
        .toList();
    final validCategory =
        c.categories.any((category) => category.id == _category)
            ? _category
            : null;
    return Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .88,
            child: Form(
                key: _form,
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 12, 4),
                      child: Row(children: [
                        Expanded(
                            child: Text(
                                readOnly
                                    ? '외부 캘린더 일정'
                                    : widget.existing == null
                                        ? '새로운 할 일'
                                        : '할 일 수정',
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800))),
                        IconButton(
                            onPressed:
                                _saving ? null : () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                            tooltip: '닫기'),
                      ])),
                  Expanded(
                      child: ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                        if (readOnly)
                          const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: Text('이 일정은 원래 캘린더 앱에서 수정할 수 있습니다.')),
                        TextFormField(
                            controller: _title,
                            readOnly: readOnly,
                            autofocus: widget.existing == null,
                            maxLength: 200,
                            decoration:
                                const InputDecoration(labelText: '무엇을 해야 하나요?'),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? '제목을 입력하세요'
                                    : null),
                        const SizedBox(height: 12),
                        TextFormField(
                            controller: _notes,
                            readOnly: readOnly,
                            minLines: 2,
                            maxLines: 5,
                            maxLength: 4000,
                            decoration: const InputDecoration(labelText: '메모')),
                        if (!readOnly) ...[
                          ..._steps.asMap().entries.map((entry) =>
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: entry.value.completed,
                                  title: Text(entry.value.title),
                                  secondary:
                                      IconButton(
                                          icon: const Icon(
                                              Icons.remove_circle_outline),
                                          onPressed:
                                              () =>
                                                  setState(() => _steps.removeAt(
                                                      entry.key))),
                                  onChanged: (value) => setState(() =>
                                      _steps[entry.key] = ChecklistStep(
                                          entry.value.title,
                                          completed: value ?? false)))),
                          TextField(
                              controller: _stepInput,
                              maxLength: 120,
                              decoration: InputDecoration(
                                  labelText: '체크리스트 단계 추가',
                                  suffixIcon: IconButton(
                                      icon: const Icon(Icons.add),
                                      onPressed: () {
                                        if (_stepInput.text.trim().isEmpty) {
                                          return;
                                        }
                                        setState(() => _steps.add(ChecklistStep(
                                            _stepInput.text.trim())));
                                        _stepInput.clear();
                                      }))),
                        ],
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                            initialValue: validCategory,
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: '카테고리'),
                            items: [
                              const DropdownMenuItem<String>(
                                  value: null, child: Text('미분류')),
                              ...c.categories
                                  .map((category) => DropdownMenuItem(
                                      value: category.id,
                                      child: Row(children: [
                                        Icon(categoryIcons[category.icon],
                                            size: 18, color: category.color),
                                        const SizedBox(width: 8),
                                        Flexible(
                                            child: Text(category.name,
                                                overflow:
                                                    TextOverflow.ellipsis))
                                      ])))
                            ],
                            onChanged: readOnly
                                ? null
                                : (value) => setState(() => _category = value)),
                        const SizedBox(height: 16),
                        Card(
                            child: Column(children: [
                          ListTile(
                              leading: const Icon(Icons.event_outlined),
                              title: Text(_date == null
                                  ? '날짜 없음'
                                  : DateFormat('yyyy년 M월 d일 EEEE', 'ko')
                                      .format(_date!)),
                              onTap: readOnly ? null : _pickDate,
                              trailing: _date == null || readOnly
                                  ? null
                                  : IconButton(
                                      onPressed: () => setState(() {
                                            _date = null;
                                            _unit = RepeatUnit.none;
                                            _reminder = null;
                                            _shift = HolidayShift.keep;
                                          }),
                                      icon: const Icon(Icons.clear),
                                      tooltip: '날짜 제거')),
                          if (_date != null) ...[
                            SwitchListTile(
                                title: const Text('종일'),
                                value: _allDay,
                                onChanged: readOnly
                                    ? null
                                    : (value) =>
                                        setState(() => _allDay = value)),
                            if (!_allDay)
                              ListTile(
                                  leading: const Icon(Icons.schedule),
                                  title:
                                      Text(DateFormat('HH:mm').format(_date!)),
                                  onTap: readOnly ? null : _pickTime),
                          ],
                        ])),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                            initialValue: _priority,
                            decoration:
                                const InputDecoration(labelText: '우선순위'),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('보통')),
                              DropdownMenuItem(value: 1, child: Text('중요')),
                              DropdownMenuItem(value: 2, child: Text('매우 중요'))
                            ],
                            onChanged: readOnly
                                ? null
                                : (value) =>
                                    setState(() => _priority = value ?? 0)),
                        if (_date != null) ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<int>(
                              initialValue: _reminder,
                              decoration:
                                  const InputDecoration(labelText: '알림'),
                              items: const [
                                DropdownMenuItem<int>(
                                    value: null, child: Text('알림 없음')),
                                DropdownMenuItem(
                                    value: 0, child: Text('예정 시간에')),
                                DropdownMenuItem(
                                    value: 10, child: Text('10분 전')),
                                DropdownMenuItem(
                                    value: 30, child: Text('30분 전')),
                                DropdownMenuItem(
                                    value: 1440, child: Text('하루 전'))
                              ],
                              onChanged: readOnly
                                  ? null
                                  : (value) =>
                                      setState(() => _reminder = value)),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<RepeatUnit>(
                              initialValue: _unit,
                              decoration:
                                  const InputDecoration(labelText: '반복'),
                              items: const [
                                DropdownMenuItem(
                                    value: RepeatUnit.none,
                                    child: Text('반복 안 함')),
                                DropdownMenuItem(
                                    value: RepeatUnit.day, child: Text('일 단위')),
                                DropdownMenuItem(
                                    value: RepeatUnit.week,
                                    child: Text('주 단위')),
                                DropdownMenuItem(
                                    value: RepeatUnit.month,
                                    child: Text('월 단위')),
                                DropdownMenuItem(
                                    value: RepeatUnit.year, child: Text('년 단위'))
                              ],
                              onChanged: readOnly
                                  ? null
                                  : (value) => setState(() {
                                        _unit = value ?? RepeatUnit.none;
                                        if (_unit == RepeatUnit.none) {
                                          _shift = HolidayShift.keep;
                                        }
                                      })),
                          if (_unit != RepeatUnit.none) ...[
                            ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('$_interval${{
                                  RepeatUnit.day: '일',
                                  RepeatUnit.week: '주',
                                  RepeatUnit.month: '개월',
                                  RepeatUnit.year: '년'
                                }[_unit]}마다 반복'),
                                trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                          onPressed: readOnly || _interval <= 1
                                              ? null
                                              : () =>
                                                  setState(() => _interval--),
                                          icon: const Icon(Icons.remove)),
                                      IconButton(
                                          onPressed: readOnly || _interval >= 99
                                              ? null
                                              : () =>
                                                  setState(() => _interval++),
                                          icon: const Icon(Icons.add)),
                                    ])),
                            DropdownButtonFormField<HolidayShift>(
                                initialValue: _shift,
                                decoration: const InputDecoration(
                                    labelText: '휴일에 해당하면'),
                                items: const [
                                  DropdownMenuItem(
                                      value: HolidayShift.keep,
                                      child: Text('원래 날짜 유지')),
                                  DropdownMenuItem(
                                      value: HolidayShift.before,
                                      child: Text('직전 업무일로 이동')),
                                  DropdownMenuItem(
                                      value: HolidayShift.after,
                                      child: Text('다음 업무일로 이동'))
                                ],
                                onChanged: readOnly
                                    ? null
                                    : (value) => setState(() =>
                                        _shift = value ?? HolidayShift.keep)),
                            if (_shift != HolidayShift.keep) ...[
                              SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('토·일요일도 휴일로 처리'),
                                  value: _weekends,
                                  onChanged: readOnly
                                      ? null
                                      : (value) =>
                                          setState(() => _weekends = value)),
                              const Text(
                                  '현재 한국 2026년 공휴일을 지원합니다. 다른 연도는 자동 이동을 확정하지 않습니다.',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                            ],
                          ],
                        ],
                        const SizedBox(height: 16),
                        DropdownButtonFormField<CalendarProvider>(
                            initialValue: _provider,
                            decoration:
                                const InputDecoration(labelText: '저장 위치'),
                            items: [
                              const DropdownMenuItem<CalendarProvider>(
                                  value: null, child: Text('이 기기만')),
                              ...c.accounts.values.map((account) =>
                                  DropdownMenuItem(
                                      value: account.provider,
                                      child: Text(account.provider ==
                                              CalendarProvider.google
                                          ? 'Google Calendar'
                                          : account.provider ==
                                                  CalendarProvider.apple
                                              ? 'Apple Calendar'
                                              : 'iCloud Calendar')))
                            ],
                            onChanged:
                                readOnly || widget.existing?.remoteKey != null
                                    ? null
                                    : (value) => setState(() {
                                          _provider = value;
                                          _calendarId = null;
                                        })),
                        if (_provider != null) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                              initialValue: calendars.any(
                                      (calendar) => calendar.id == _calendarId)
                                  ? _calendarId
                                  : null,
                              isExpanded: true,
                              decoration:
                                  const InputDecoration(labelText: '대상 캘린더'),
                              items: calendars
                                  .map((calendar) => DropdownMenuItem(
                                      value: calendar.id,
                                      child: Text(calendar.name)))
                                  .toList(),
                              onChanged:
                                  readOnly || widget.existing?.remoteKey != null
                                      ? null
                                      : (value) =>
                                          setState(() => _calendarId = value)),
                          const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                  '설정에서 선택한 쓰기 가능한 캘린더가 표시됩니다. '
                                  '반복 할 일은 현재 기기 내 저장을 지원합니다.',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey))),
                        ],
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: Text(_error!,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error))),
                      ])),
                  if (!readOnly)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                        child: Row(children: [
                          if (widget.existing != null)
                            IconButton(
                                onPressed: _saving ? null : _delete,
                                icon: const Icon(Icons.delete_outline),
                                tooltip: '삭제'),
                          const SizedBox(width: 12),
                          Expanded(
                              child: FilledButton.icon(
                                  onPressed: _saving ? null : _save,
                                  icon: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.check),
                                  label: Text(_saving ? '저장 중…' : '저장'),
                                  style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.all(16)))),
                        ])),
                ]))));
  }
}
