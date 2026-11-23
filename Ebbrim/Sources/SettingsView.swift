import SwiftUI

/// Settings, opened from the gear at the end of the hovered pill (or the
/// menu): every source with the control that connects or disconnects it,
/// Open at Login, the notch's edge, and a way back to the welcome tour.
/// Switches only ask the data layer; what they show is its real answer.
struct SettingsView: View {
    @ObservedObject var feed: UsageFeed
    @ObservedObject var model: NotchModel
    let onEdge: (Edge) -> Void
    let onRefresh: () -> Void
    var onWelcome: () -> Void = {}

    var body: some View {
        // The window has a normal title bar ("Settings"), so nothing scrolls
        // under the window buttons; the list scrolls in its own space.
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("Sources") {
                    SourceRow(source: .claudeDesktop, feed: feed)
                    if SourceRow.showsTerminal(feed: feed) {
                        SourceRow(source: .terminal, feed: feed, nested: true)
                    }
                    Hairline()
                    SourceRow(source: .codex, feed: feed)
                }

                section("Appearance") {
                    AppearanceRow(source: .claudeDesktop, feed: feed, model: model); Hairline()
                    AppearanceRow(source: .codex, feed: feed, model: model)
                }

                section("General") {
                    LoginRow(feed: feed)
                    Hairline()
                    ServersRow(feed: feed)
                    Hairline()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Where the notch sits").font(SetupStyle.rowTitle).foregroundStyle(.white)
                        EdgePicker(edge: model.edge, onEdge: onEdge)
                        Text("You can also drag the notch to any of these edges.")
                            .font(SetupStyle.rowBody).foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.vertical, 14)
                    Hairline()
                    UninstallRow(feed: feed)
                }

                HStack(spacing: 10) {
                    TextButton(title: "Show the welcome tour", action: onWelcome)
                    Spacer()
                    PillButton(title: "Refresh now", action: onRefresh)
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 22)
        }
        .scrollIndicators(.automatic)
        .frame(width: 560, height: 600)
        .background(SetupStyle.bg)
        .preferredColorScheme(.dark)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(CardType.tag).tracking(0.9).foregroundStyle(.white.opacity(0.45))
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 16)
                .background(SetupStyle.row, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
        }
    }
}
