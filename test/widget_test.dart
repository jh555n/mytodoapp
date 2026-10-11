import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:dayweave/app_controller.dart';
import 'package:dayweave/data/store.dart';
import 'package:dayweave/domain/recurrence.dart';
import 'package:dayweave/ui/app.dart';

void main() {
  sqfliteFfiInit();
  testWidgets(
      'quick add saves a real Todo and calendar/category navigation stays usable',
      (tester) async {
    final store = await TodoStore.open(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    final controller = AppController(
        store: store,
        engine: RecurrenceEngine(HolidayCalendar({}, coveredYears: {2026})),
        connectors: {});
    await controller.load();
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: HomeScreen(controller: controller, handleDeepLinks: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('할 일 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '테스트 할 일');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(controller.todos.single.title, '테스트 할 일');
    expect(find.text('테스트 할 일'), findsOneWidget);
    await tester.tap(find.text('캘린더'));
    await tester.pumpAndSettle();
    expect(find.text('나의 캘린더'), findsOneWidget);
    await tester.tap(find.text('카테고리'));
    await tester.pumpAndSettle();
    expect(find.text('나만의 카테고리'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await store.close();
  });
}
