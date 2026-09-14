import WidgetKit
import SwiftUI
import AppIntents

struct IndicatorConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Duolet Appearance"
    static var description = IntentDescription("Choose whether to show the battery percentage above the connection.")

    @Parameter(title: "Battery Percentage", default: false)
    var showsPercentage: Bool
}

struct StatusEntry: TimelineEntry {
    let date: Date
    let status: DeviceStatus
    var showsPercentage = false
}

struct StatusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, status: .preview)
    }
    func snapshot(for configuration: IndicatorConfiguration, in context: Context) async -> StatusEntry {
        if context.isPreview {
            return StatusEntry(date: .now, status: .preview, showsPercentage: configuration.showsPercentage)
        }
        return await load(showsPercentage: configuration.showsPercentage)
    }
    func timeline(for configuration: IndicatorConfiguration, in context: Context) async -> Timeline<StatusEntry> {
        let entry = await load(showsPercentage: configuration.showsPercentage)
        return Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(15 * 60)))
    }
    private func load(showsPercentage: Bool) async -> StatusEntry {
        await withCheckedContinuation { continuation in
            let reader = NetworkSnapshot()
            reader.read { [reader] connection in
                _ = reader // Retain the one-shot reader until the first update or timeout.
                continuation.resume(returning: StatusEntry(date: .now,
                    status: DeviceStatus(power: .read(), connection: connection),
                    showsPercentage: showsPercentage))
            }
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
                      inactiveOpacity: contrast == .increased ? 0.45 : (renderingMode == .fullColor ? 0.19 : 0.28),
                      showsPercentage: entry.showsPercentage,
                      lowBatteryInk: renderingMode == .fullColor ? .red : nil)
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
        AppIntentConfiguration(kind: kind, intent: IndicatorConfiguration.self, provider: StatusProvider()) { entry in
            WidgetIndicator(entry: entry)
        }
        .configurationDisplayName("Duolet")
        .description("Battery around the arc. Connection in the center. Solid dots for external power.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
    }
}
