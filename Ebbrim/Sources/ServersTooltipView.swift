import SwiftUI

/// Hover card content for local dev servers (Figma 2192:24987): header with
/// the active count, a list that scrolls past a max height with a fade at
/// the bottom, and the totals underneath.
struct ServersTooltipView: View {
    let servers: [LocalServer]
    var extra: Int = 0
    let onOpen: (LocalServer) -> Void
    let onKill: (LocalServer) -> Void

    static let listMaxH: CGFloat = 166
    @State private var listH: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if servers.isEmpty {
                StateNote(icon: "moon.zzz.fill", tint: .white.opacity(0.6),
                          title: "No servers running",
                          detail: "Dev servers on localhost show up here on their own.")
                    .padding(.top, 2)
            } else {
                list
                footer
            }
        }
        .padding(CardMetrics.pad)
        .frame(width: CardMetrics.width, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(nsImage: Marks.database).resizable().frame(width: 16, height: 16)
                Text("Local servers").font(CardType.title).tracking(-0.15).foregroundStyle(.white)
            }
            Spacer(minLength: 8)
            let n = servers.count + extra
            Text(n == 0 ? "None active" : "\(n) active")
                .font(.custom("Inter", size: 13).weight(.medium).monospacedDigit())
                .tracking(-0.2)
                .foregroundStyle(n == 0 ? .white.opacity(0.45) : .white)
                .contentTransition(.numericText(value: Double(n)))
        }
    }

    private var rows: some View {
        VStack(spacing: 6) {
            ForEach(servers) { ServerRow(server: $0, onOpen: onOpen, onKill: onKill) }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { listH = $0 }
    }

    @ViewBuilder private var list: some View {
        let scrolls = listH > Self.listMaxH
        if !scrolls {
            rows
        } else {
            scroller
        }
    }

    private var scroller: some View {
        ScrollView(.vertical) { rows }
            .scrollIndicators(.never)
            .frame(height: Self.listMaxH)
            .mask {
                // Fade the last rows out when there's more to scroll to.
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.86),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
    }

    private var footer: some View {
        HStack {
            if extra > 0 { Text("+\(extra) more") }
            Spacer()
            Text(String(format: "%.0f%% CPU · %d MB", totalCPU, totalMem))
        }
        .font(CardType.caption)
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 2)
    }

    private var totalCPU: Double { servers.reduce(0) { $0 + $1.cpu } }
    private var totalMem: Int { servers.reduce(0) { $0 + $1.memMB } }
}

private struct ServerRow: View {
    let server: LocalServer
    let onOpen: (LocalServer) -> Void
    let onKill: (LocalServer) -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(server.project)
                        .font(.custom("Inter", size: 12)).foregroundStyle(.white)
                        .lineLimit(1).truncationMode(.middle)
                    Text(verbatim: ":\(server.port)")
                        .font(.custom("Inter", size: 9).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Text(verbatim: "\(server.kind) · \(String(format: "%.0f%%", server.cpu)) CPU · \(server.memMB) MB")
                    .font(CardType.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            RoundIcon(symbol: "arrow.up.right", tint: .white, bg: .white.opacity(0.1)) { onOpen(server) }
            RoundIcon(symbol: "xmark", tint: Theme.red, bg: Theme.red.opacity(0.18)) { onKill(server) }
        }
        .padding(.vertical, 7).padding(.horizontal, 9)
        .background(.white.opacity(hovered ? 0.09 : 0.06),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovered = $0 }
        .animation(.smooth(duration: 0.14), value: hovered)
    }
}

/// Small circular icon button.
private struct RoundIcon: View {
    let symbol: String
    let tint: Color
    let bg: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(bg.opacity(hovered ? 1.6 : 1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
