import Flutter
import UIKit
import EventKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let eventStore = EKEventStore()

  override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    FlutterMethodChannel(name: "dev.dayweave/calendar", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard let self else { return }
        self.handleCalendar(call, result)
      }
    FlutterMethodChannel(name: "dev.dayweave/privacy", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "excludeFromBackup" else { result(FlutterMethodNotImplemented); return }
        do {
          for directory in [FileManager.SearchPathDirectory.documentDirectory, .applicationSupportDirectory] {
            var url = try FileManager.default.url(for: directory, in: .userDomainMask,
              appropriateFor: nil, create: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
          }
          result(nil)
        } catch { result(FlutterError(code: "backup", message: "자동 백업 제외 설정에 실패했습니다.", details: nil)) }
      }
  }

  private func hasAccess() -> Bool {
    let status = EKEventStore.authorizationStatus(for: .event)
    if #available(iOS 17.0, *) { return status == .fullAccess }
    return status == .authorized
  }
  private func fail(_ result: FlutterResult, _ message: String) {
    result(FlutterError(code: "calendar", message: message, details: nil))
  }
  private func revision(_ event: EKEvent) -> String {
    return String(event.lastModifiedDate?.timeIntervalSince1970 ?? 0)
  }
  private func owned(_ event: EKEvent) -> Bool {
    return event.url?.scheme == "dayweave" && event.url?.host == "todo" && (event.recurrenceRules?.isEmpty ?? true)
  }
  private func handleCalendar(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    if call.method == "requestAccess" {
      let callback: (Bool, Error?) -> Void = { granted, _ in
        DispatchQueue.main.async {
          if granted { result(nil) }
          else { self.fail(result, "기기 설정에서 캘린더 전체 접근을 허용하세요.") }
        }
      }
      if #available(iOS 17.0, *) { eventStore.requestFullAccessToEvents(completion: callback) }
      else { eventStore.requestAccess(to: .event, completion: callback) }
      return
    }
    if call.method == "disconnect" { eventStore.reset(); result(nil); return }
    guard hasAccess() else { fail(result, "캘린더 접근 권한이 철회되었습니다. 다시 연결하세요."); return }
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "calendars":
      result(eventStore.calendars(for: .event).map { calendar in
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(cgColor: calendar.cgColor).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let color = 0xFF000000 | (Int(red * 255) << 16) | (Int(green * 255) << 8) | Int(blue * 255)
        return ["id": calendar.calendarIdentifier, "name": calendar.title,
          "color": color, "writable": calendar.allowsContentModifications] as [String: Any]
      })
    case "events":
      guard let calendarID = args["calendarId"] as? String,
        let calendar = eventStore.calendar(withIdentifier: calendarID),
        let from = args["from"] as? NSNumber, let until = args["until"] as? NSNumber else {
        fail(result, "캘린더 조회 범위를 확인하세요."); return
      }
      let predicate = eventStore.predicateForEvents(withStart: Date(timeIntervalSince1970: from.doubleValue / 1000),
        end: Date(timeIntervalSince1970: until.doubleValue / 1000), calendars: [calendar])
      result(eventStore.events(matching: predicate).map { event in
        let managed = self.owned(event)
        // Expanded recurrence instances share identifiers; add the occurrence timestamp.
        let id = managed ? event.eventIdentifier! : "\(event.eventIdentifier!)@\(event.startDate.timeIntervalSince1970)"
        let complete = URLComponents(url: event.url ?? URL(string: "dayweave://none")!,
          resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "completed" })?.value == "true"
        return ["id": id, "title": event.title ?? "(제목 없음)", "notes": event.notes ?? "",
          "startsAt": Int(event.startDate.timeIntervalSince1970 * 1000), "allDay": event.isAllDay,
          "updatedAt": Int((event.lastModifiedDate ?? event.startDate).timeIntervalSince1970 * 1000),
          "revision": self.revision(event), "managed": managed, "completed": complete] as [String: Any]
      })
    case "save":
      guard let calendarID = args["calendarId"] as? String,
        let calendar = eventStore.calendar(withIdentifier: calendarID), calendar.allowsContentModifications,
        let title = args["title"] as? String, let milliseconds = args["startsAt"] as? NSNumber else {
        fail(result, "쓰기 가능한 캘린더와 날짜가 필요합니다."); return
      }
      let event: EKEvent
      if let id = args["id"] as? String {
        guard let existing = eventStore.event(withIdentifier: id), owned(existing) else {
          fail(result, "원본 일정이 없거나 앱이 관리하는 일정이 아닙니다. 먼저 새로고침하세요."); return
        }
        if let previous = args["revision"] as? String, revision(existing) != previous {
          fail(result, "외부에서 변경된 일정입니다. 먼저 새로고침하세요."); return
        }
        event = existing
      } else { event = EKEvent(eventStore: eventStore) }
      event.calendar = calendar; event.title = title; event.notes = args["notes"] as? String
      event.startDate = Date(timeIntervalSince1970: milliseconds.doubleValue / 1000)
      event.isAllDay = args["allDay"] as? Bool ?? true
      event.endDate = event.isAllDay ? Calendar.current.date(byAdding: .day, value: 1, to: event.startDate) :
        event.startDate.addingTimeInterval(1800)
      let marker = event.url?.path ?? "/\(UUID().uuidString)"
      let complete = args["completed"] as? Bool ?? false
      event.url = URL(string: "dayweave://todo\(marker)?completed=\(complete)")
      do {
        try eventStore.save(event, span: .thisEvent, commit: true)
        result(["id": event.eventIdentifier!, "revision": revision(event)])
      } catch { fail(result, "캘린더에 저장하지 못했습니다.") }
    case "delete":
      guard let id = args["id"] as? String else { fail(result, "일정 ID가 필요합니다."); return }
      guard let event = eventStore.event(withIdentifier: id) else { result(nil); return }
      guard owned(event) else { fail(result, "앱이 관리하는 일정만 삭제할 수 있습니다."); return }
      if let previous = args["revision"] as? String, revision(event) != previous {
        fail(result, "외부에서 변경된 일정입니다. 먼저 새로고침하세요."); return
      }
      do { try eventStore.remove(event, span: .thisEvent, commit: true); result(nil) }
      catch { fail(result, "캘린더에서 삭제하지 못했습니다.") }
    default: result(FlutterMethodNotImplemented)
    }
  }
}
