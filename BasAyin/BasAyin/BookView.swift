import SwiftUI

/// The sections of one book of the Torah, in the order of the edition, or the festivals
/// and special Shabbatot from Tishrei to Shavuot, or the likkutim and responsa.
struct SectionListView: View {
    let group: SectionGroup
    @Binding var path: NavigationPath
    @Environment(AppSettings.self) private var settings
    @Environment(TextStore.self) private var store

    var body: some View {
        List {
            ForEach(store.sections(in: group)) { section in
                Button {
                    path.append(ReadingRoute.section(id: section.id, scrollTo: nil))
                } label: {
                    CenteredMenuRow(title: section.name(for: settings.language))
                }
                .accessibilityIdentifier("section.\(section.id)")
                .buttonStyle(.plain)
                .modifier(FullWidthDividerRow())
            }
        }
        .modifier(MenuListStyle())
        .listRowSeparator(.hidden)
        .environment(\.defaultMinListRowHeight, 56)
        .studyBar(title: store.groupTitle(group, language: settings.language))
    }
}

struct ResumeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TextStore.self) private var store
    @Environment(UserLibrary.self) private var library
    @Environment(\.colorScheme) private var scheme
    /// The place to resume, fixed when this screen opens. Reading here moves
    /// `lastParagraphID`; following it would rebuild the whole page each time.
    @State private var openedAt: Int?

    var body: some View {
        let id = openedAt ?? library.lastParagraphID
        Group {
            if let id, let paragraph = store.paragraph(id: id) {
                ReadingView(route: library.route(for: paragraph))
            } else if id != nil {
                message(L10n.text("reading.missingPlace", settings.language))
            } else {
                message(L10n.text("home.resume.empty", settings.language))
            }
        }
        .onAppear {
            if openedAt == nil {
                openedAt = library.lastParagraphID
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.menuFont(settings.language))
            .foregroundStyle(Theme.secondary(scheme))
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background(scheme))
            .studyBar(title: L10n.text("home.resume", settings.language))
    }
}

struct WeeklyView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TextStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if !store.readingCoversToday() {
            message(
                String(
                    format: L10n.text("home.weekly.outOfRange", settings.language),
                    store.yearStart,
                    store.yearEnd
                )
            )
        } else if let reading = store.currentReading(israel: settings.israelCalendar), !reading.sectionIDs.isEmpty {
            ReadingView(route: .weekly(
                ids: reading.sectionIDs,
                titleHe: reading.titleHe,
                titleEn: reading.titleEn,
                scrollTo: nil
            ))
        } else {
            message(L10n.text("home.weekly.empty", settings.language))
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.menuFont(settings.language))
            .foregroundStyle(Theme.secondary(scheme))
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background(scheme))
            .studyBar(title: L10n.text("home.weekly", settings.language))
    }
}
