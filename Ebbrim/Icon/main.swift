import SwiftUI
import AppKit

/// Ebbrim's app icon on the macOS 26 grid: a 824 pt continuous squircle on a
/// 1024 canvas, the dark glass of the app, and the logo mark in the middle.
struct EbbrimAppIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.05)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 3)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            // The mark spans x 0…51 of the logo's 239.22 × 53 space: draw the
            // whole logo box and shift it so the mark sits in the centre.
            let h: CGFloat = 400
            EbbrimMark()
                .fill(LinearGradient(colors: [.white, Color(white: 0.604)],
                                     startPoint: UnitPoint(x: 3.9 / 239.22, y: 0.5),
                                     endPoint: UnitPoint(x: 51 / 239.22, y: 0.5)),
                      style: FillStyle(eoFill: true))
                .frame(width: h * 239.22 / 53, height: h)
                .offset(x: (h * 239.22 / 53) / 2 - (h * 51 / 53) / 2)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func renderIcon(to url: URL) {
    let r = ImageRenderer(content: EbbrimAppIcon())
    r.scale = 1
    guard let cg = r.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

MainActor.assumeIsolated { renderIcon(to: URL(fileURLWithPath: CommandLine.arguments[1])) }
