import SwiftUI

struct HomeView: View {
    var onOpen: (SidebarItem) -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(TextStore.self) private var store
    @Environment(UserLibrary.self) private var library

    var body: some View {
        List {
            row(.resume, title: L10n.text("home.resume", settings.language), subtitle: resumeSubtitle)
            row(.history, title: L10n.text("home.history", settings.language), subtitle: nil)
            row(.weekly, title: L10n.text("home.weekly", settings.language), subtitle: weeklySubtitle)
            row(.search, title: L10n.text("home.search", settings.language), subtitle: nil)
            ForEach(store.books) { book in
                row(.sections(.book(book.id)), title: book.name(for: settings.language), subtitle: nil)
            }
            row(
                .sections(.moadim),
                title: L10n.text("home.moadim", settings.language),
                subtitle: nil
            )
            row(
                .sections(.appendix),
                title: L10n.text("home.appendix", settings.language),
                subtitle: nil
            )
            row(.settings, title: L10n.text("home.settings", settings.language), subtitle: nil)
            row(.help, title: L10n.text("home.help", settings.language), subtitle: nil)
            row(.about, title: L10n.text("home.about", settings.language), subtitle: nil)
        }
        .modifier(MenuListStyle())
        .listRowSeparator(.hidden)
        .environment(\.defaultMinListRowHeight, 56)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image("ToolbarMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                    Text(L10n.text("app.title", settings.language))
                        .font(Theme.titleFont(for: L10n.text("app.title", settings.language)))
                        .foregroundStyle(Color.white)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(L10n.text("app.title", settings.language))
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(L10n.text("a11y.share", settings.language))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onOpen(.favourites)
                } label: {
                    Image(systemName: "star")
                }
                .accessibilityLabel(L10n.text("a11y.favourites", settings.language))
                .accessibilityIdentifier("home.favourites")
            }
        }
        .navigationTitle(L10n.text("app.title", settings.language))
    }

    private func row(_ item: SidebarItem, title: String, subtitle: String?) -> some View {
        Button {
            onOpen(item)
        } label: {
            CenteredMenuRow(title: title, subtitle: subtitle)
        }
        .accessibilityIdentifier(item.accessibilityID)
        .buttonStyle(.plain)
        .modifier(FullWidthDividerRow())
    }

    private var resumeSubtitle: String? {
        guard let id = library.lastParagraphID else {
            return L10n.text("home.resume.empty", settings.language)
        }
        guard let paragraph = store.paragraph(id: id) else {
            return L10n.text("reading.missingPlace", settings.language)
        }
        return store.locationTitle(for: paragraph, language: settings.language)
    }

    private var weeklySubtitle: String? {
        guard store.readingCoversToday() else {
            return String(
                format: L10n.text("home.weekly.outOfRange", settings.language),
                store.yearStart,
                store.yearEnd
            )
        }
        guard let reading = store.currentReading(israel: settings.israelCalendar) else {
            return L10n.text("home.weekly.empty", settings.language)
        }
        return reading.title(for: settings.language)
    }

    private var shareText: String {
        if let reading = store.currentReading(israel: settings.israelCalendar) {
            return String(format: L10n.text("share.app", settings.language), reading.title(for: settings.language))
        }
        return L10n.text("app.title", settings.language)
    }
}
