import AppKit
import SwiftUI

enum JournalPalette {
    static let leatherTop = adaptive(light: 0x721F30, dark: 0x3A0C15)
    static let leatherBottom = adaptive(light: 0x4F111D, dark: 0x25070D)
    static let card = adaptive(light: 0xE8D5AF, dark: 0xD8BE91)
    static let cardOpaque = adaptive(light: 0xE8D5AF, dark: 0xD8BE91)
    static let raised = adaptive(light: 0x812A3A, dark: 0x591823)
    static let ink = adaptive(light: 0xFFF4DE, dark: 0xFAEED6)
    static let secondaryInk = adaptive(light: 0xE2C9B8, dark: 0xD5BCAE)
    static let paperInk = adaptive(light: 0x3F271E, dark: 0x342018)
    static let paperSecondaryInk = adaptive(light: 0x715448, dark: 0x63483C)
    static let paperRule = adaptive(light: 0xB99B70, dark: 0xA8895F)
    static let ember = adaptive(light: 0xF3BC72, dark: 0xE5A45E)
    static let rule = adaptive(light: 0xA5505C, dark: 0x792B38)
    static let success = adaptive(light: 0xBFD18B, dark: 0xB5C986)
    static let danger = adaptive(light: 0xFFB0A8, dark: 0xF3A49D)

    static func projectAccent(for tag: String?) -> Color {
        switch tag {
        case "ember": adaptive(light: 0xF29B62, dark: 0xEEA166)
        case "gold": adaptive(light: 0xE9C46A, dark: 0xE6C674)
        case "forest": adaptive(light: 0x82A879, dark: 0x8FB387)
        case "slate": adaptive(light: 0xA5AFBB, dark: 0xABB4BF)
        default: adaptive(light: 0xE98593, dark: 0xDE7C8A)
        }
    }

    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return nsColor(hex: match == .darkAqua ? dark : light)
        })
    }

    private static func nsColor(hex: Int) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum JournalTypography {
    static let journalTitle = Font.system(.largeTitle, design: .serif, weight: .semibold)
    static let sectionTitle = Font.system(.title3, design: .serif, weight: .semibold)
    static let date = Font.system(.subheadline, design: .rounded, weight: .medium)
    static let eyebrow = Font.system(.caption2, design: .rounded, weight: .bold)
}
