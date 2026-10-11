import 'package:flutter/material.dart';
import 'app_controller.dart';
import 'data/store.dart';
import 'domain/models.dart';
import 'domain/recurrence.dart';
import 'services/apple_calendar.dart';
import 'services/google_calendar.dart';
import 'services/icloud_calendar.dart';
import 'services/notifications.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final store = await TodoStore.open();
    final holidays = await AppController.loadHolidays();
    final reminders = ReminderService();
    String? warning;
    try {
      await reminders.initialize();
    } catch (_) {
      warning = '알림 초기화에 실패했습니다. 기기에서 권한과 시간대 설정을 확인하세요.';
    }
    final controller = AppController(
        store: store,
        engine: RecurrenceEngine(holidays),
        reminders: reminders,
        connectors: {
          CalendarProvider.google: GoogleCalendarConnector(),
          CalendarProvider.apple: AppleCalendarConnector(),
          CalendarProvider.icloud: ICloudCalendarConnector()
        });
    await controller.load();
    try {
      await NativePrivacy.excludeFromBackup();
    } catch (_) {
      warning = '자동 백업 제외 설정을 확인하지 못했습니다. 네이티브 설정을 확인하세요.';
    }
    controller.warning = warning;
    await controller.scheduleReminders();
    runApp(DayweaveApp(controller: controller));
  } catch (_) {
    runApp(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                        '기기 저장소를 열지 못했습니다. 앱을 다시 시작해 주세요.\n'
                        '문제가 계속되면 저장 공간과 앱 권한을 확인하세요.',
                        textAlign: TextAlign.center))))));
  }
}
