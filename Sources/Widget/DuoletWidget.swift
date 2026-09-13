import WidgetKit
import SwiftUI

struct StatusEntry: TimelineEntry {
    let date: Date
    let status: DeviceStatus
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, status: .preview)
    }
    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)) }
        else { load(completion: completion) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        load { entry in
            completion(Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(15 * 60))))
        }
    }
    private func load(completion: @escaping (StatusEntry) -> Void) {
        let reader = NetworkSnapshot()
        reader.read { [reader] connection in
            _ = reader // Retain the one-shot reader until the first update or timeout.
            completion(StatusEntry(date: .now, status: DeviceStatus(power: .read(), connection: connection)))
        }
    }
}

private struct WidgetIndicator: View {
    let entry: StatusEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        IndicatorView(status: entry.status,
                      ink: renderingMode == .fullColor ? .black : .white,
                      inactiveOpacity: contrast == .increased ? 0.45 : (renderingMode == .fullColor ? 0.19 : 0.28))
            .padding(12)
            .widgetAccentable()
            // The system removes this background and supplies glass in clear/tinted mode.
            .containerBackground(for: .widget) { IndicatorView.background }
            .widgetURL(URL(string: "duolet://show"))
    }
}

@main
struct DuoletWidget: Widget {
    let kind = "DuoletWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
            WidgetIndicator(entry: entry)
        }
        .configurationDisplayName("Duolet")
        .description("Battery around the arc. Connection in the center. Solid dots for external power.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
    }
}
