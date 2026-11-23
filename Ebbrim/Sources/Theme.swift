import SwiftUI

/// Colors and type of the notch and its hover cards.
enum Theme {
    // Levels: what's left goes grey (plenty) → yellow → red.
    static let green  = Color(red: 0.25, green: 0.78, blue: 0.35)
    static let yellow = Color(red: 0.90, green: 0.72, blue: 0.15)
    static let red    = Color(red: 0.95, green: 0.18, blue: 0.22)

    // Minimal notch (Figma 2179:831)
    static let claudeOrange = Color(red: 1.0, green: 0x7D / 255.0, blue: 0x3B / 255.0)   // #FF7D3B
    static let notchTrack = Color(white: 0x31 / 255.0)                                // #313131
    static let notchMuted = Color(white: 0x6F / 255.0)                                // #6F6F6F
    /// Inter Regular 10 as in the design; falls back to the system font.
    static let notchFont = Font.custom("Inter", size: 10)

    /// "42%" — rounded, never clamped (a source may report >100).
    static func pct(_ used: Double) -> String { "\(Int(used.rounded()))%" }
}

/// Type scale for the hover cards (Inter): one size per role, tabular
/// digits wherever numbers change, tighter tracking as sizes grow.
enum CardType {
    static let title = Font.custom("Inter", size: 13).weight(.semibold)        // tracking -0.15
    static let value = Font.custom("Inter", size: 17).weight(.medium).monospacedDigit()  // tracking -0.4
    static let body = Font.custom("Inter", size: 11).weight(.medium)
    static let caption = Font.custom("Inter", size: 10.5).monospacedDigit()   // tracking 0.05
    static let tag = Font.custom("Inter", size: 9).weight(.semibold)          // tracking 0.2
}
