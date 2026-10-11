import WidgetKit
import SwiftUI

struct QuickAddEntry: TimelineEntry { let date: Date }
struct QuickAddProvider: TimelineProvider {
  func placeholder(in context: Context) -> QuickAddEntry { QuickAddEntry(date: Date()) }
  func getSnapshot(in context: Context, completion: @escaping (QuickAddEntry) -> Void) {
    completion(QuickAddEntry(date: Date()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<QuickAddEntry>) -> Void) {
    completion(Timeline(entries: [QuickAddEntry(date: Date())], policy: .never))
  }
}

struct QuickAddView: View {
  @Environment(\.widgetFamily) var family
  var body: some View {
    Group {
      if family == .accessoryCircular { Image(systemName: "plus.circle.fill").font(.title) }
      else if family == .accessoryInline { Label("할 일 추가", systemImage: "plus.circle") }
      else {
        VStack(alignment: .leading, spacing: 8) {
          Image(systemName: "plus.circle.fill").font(.largeTitle).foregroundStyle(.indigo)
          Text("할 일 추가").font(.headline)
          if family == .systemSmall { Text("dayweave").font(.caption).foregroundStyle(.secondary) }
        }
      }
    }
    .widgetURL(URL(string: "dayweave://add"))
    .containerBackground(for: .widget) { Color.clear }
  }
}

@main
struct QuickAddWidget: Widget {
  let kind = "DayweaveQuickAdd"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QuickAddProvider()) { _ in QuickAddView() }
      .configurationDisplayName("빠른 할 일 등록")
      .description("잠금 해제 후 바로 할 일을 추가합니다. 데이터는 위젯에 표시하지 않습니다.")
      .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}
