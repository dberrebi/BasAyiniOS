import SwiftUI

struct HistoryView: View {
    @Binding var path: NavigationPath
    @Environment(AppSettings.self) private var settings
    @Environment(TextStore.self) private var store
    @Environment(UserLibrary.self) private var library
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if library.history.isEmpty {
                empty(L10n.text("history.empty", settings.language))
            } else {
                List(library.history) { entry in
                    if let paragraph = store.paragraph(id: entry.paragraphID) {
                        Button {
                            path.append(library.route(for: paragraph))
                        } label: {
                            CenteredMenuRow(
                                title: store.locationTitle(for: paragraph, language: settings.language),
                                subtitle: HebrewText.preview(paragraph)
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .listRowBackground(Theme.background(scheme))
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .listRowSeparatorTint(Theme.divider(scheme))
                    }
                }
                .modifier(MenuListStyle())
            }
        }
        .studyBar(title: L10n.text("history.title", settings.language))
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(Theme.menuFont(settings.language))
            .foregroundStyle(Theme.secondary(scheme))
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background(scheme))
    }
}

struct FavouritesView: View {
    @Binding var path: NavigationPath
    @Environment(AppSettings.self) private var settings
    @Environment(TextStore.self) private var store
    @Environment(UserLibrary.self) private var library
    @Environment(\.colorScheme) private var scheme

    private var paragraphs: [Paragraph] {
        library.favouriteIDs.compactMap { store.paragraph(id: $0) }
    }

    var body: some View {
        Group {
            if paragraphs.isEmpty {
                Text(L10n.text("favourites.empty", settings.language))
                    .font(Theme.menuFont(settings.language))
                    .foregroundStyle(Theme.secondary(scheme))
                    .multilineTextAlignment(.center)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background(scheme))
            } else {
                List(paragraphs) { paragraph in
                    Button {
                        path.append(library.route(for: paragraph))
                    } label: {
                        CenteredMenuRow(
                            title: store.locationTitle(for: paragraph, language: settings.language),
                            subtitle: HebrewText.preview(paragraph)
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .listRowBackground(Theme.background(scheme))
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowSeparatorTint(Theme.divider(scheme))
                }
                .modifier(MenuListStyle())
            }
        }
        .studyBar(title: L10n.text("favourites.title", settings.language))
    }
}
