import SwiftUI
import UIKit

/// Safed blue and gold. The author settled in Safed in 1831.
enum Theme {
    static let bar = Color(red: 0.067, green: 0.114, blue: 0.200)
    static let barUIColor = UIColor(red: 0.067, green: 0.114, blue: 0.200, alpha: 1)
    static let accent = Color(red: 0.776, green: 0.631, blue: 0.357)
    static let hebrewFamily = "Noto Serif Hebrew"

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.051, green: 0.071, blue: 0.110)
            : Color(red: 0.965, green: 0.945, blue: 0.906)
    }

    static func text(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.945, green: 0.929, blue: 0.894)
            : Color(red: 0.098, green: 0.114, blue: 0.157)
    }

    static func secondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.729, green: 0.737, blue: 0.765)
            : Color(red: 0.333, green: 0.341, blue: 0.380)
    }

    static func emphasis(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.886, green: 0.741, blue: 0.455)
            : Color(red: 0.122, green: 0.278, blue: 0.522)
    }

    static func divider(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.14)
    }

    static func menuFont(_ language: AppLanguage) -> Font {
        if language == .he {
            return .custom(hebrewFamily, size: 22, relativeTo: .title3)
        }
        return .title3
    }

    static func hebrewFont(size: CGFloat, emphasis: Bool) -> Font {
        let base = Font.custom(hebrewFamily, size: size, relativeTo: .body)
        return emphasis ? base.weight(.bold) : base
    }

    static func containsHebrew(_ text: String) -> Bool {
        HebrewText.containsHebrew(text)
    }

    static func titleFont(for title: String) -> Font {
        if containsHebrew(title) {
            return .custom(hebrewFamily, size: 18, relativeTo: .headline)
        }
        return .headline
    }
}

struct StudyBar: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(Theme.titleFont(for: title))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}

extension View {
    func studyBar(title: String) -> some View {
        modifier(StudyBar(title: title))
    }
}

/// Hides the system list separator, which stops at the title, and draws one hairline across the row.
struct FullWidthDividerRow: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.divider(scheme))
                    .frame(height: 0.5)
                    .frame(maxWidth: .infinity)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.background(scheme))
            .contentShape(Rectangle())
    }
}

enum StatusBarChrome {
    /// The top bar is always dark, so its status-bar icons stay light in both appearances.
    static func install() {
        let bar = UINavigationBar.appearance()
        bar.isTranslucent = false
        bar.overrideUserInterfaceStyle = .dark
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Theme.barUIColor
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.shadowColor = .clear
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance
        bar.compactScrollEdgeAppearance = appearance
        bar.tintColor = .white
    }
}
