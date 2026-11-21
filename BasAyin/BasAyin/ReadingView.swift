import SwiftUI
import UIKit

private struct ReadingAnchor: Equatable {
    let id: Int
    let minY: CGFloat
}

private struct ReadingAnchorKey: PreferenceKey {
    static var defaultValue: [ReadingAnchor] = []
    static func reduce(value: inout [ReadingAnchor], nextValue: () -> [ReadingAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

/// One lazy row. A paragraph is its own row, with the same `id` the reader already
/// scrolls to, so resume and search can land on it without building the section first.
private enum ReadingRow: Identifiable {
    /// The section's name, when a reading joins several sections.
    case header(sectionID: Int)
    /// The verse a derush opens on, above that paragraph.
    case citation(paragraphID: Int, citation: VerseCitation)
    case paragraph(Paragraph)
    /// A button to the section where a one-line pointer says the derashot are printed.
    case redirect(sectionID: Int, targetID: Int)

    var id: String {
        switch self {
        case .header(let sectionID):
            return "h-\(sectionID)"
        case .citation(let paragraphID, _):
            return "v-\(paragraphID)"
        case .paragraph(let paragraph):
            return "p-\(paragraph.id)"
        case .redirect(let sectionID, _):
            return "r-\(sectionID)"
        }
    }
}

struct ReadingView: View {
    let route: ReadingRoute
    @Environment(AppSettings.self) private var settings
    @Environment(TextStore.self) private var store
    @Environment(UserLibrary.self) private var library
    @Environment(\.colorScheme) private var scheme
    @State private var rows: [ReadingRow] = []
    @State private var allowTracking = false
    @State private var trackedParagraphID: Int?
    @State private var initialTopID: Int?
    @State private var topID: Int?
    @State private var hasScrolled = false
    @State private var dwell: Task<Void, Never>?

    /// A paragraph becomes the saved place only after it stays at the top this long
    /// once the reader has scrolled, so flicking through a section does not count.
    private static let settleDelay: UInt64 = 4_000_000_000
    /// Without any scrolling, the paragraph a screen opened on counts only after this
    /// long (20 seconds), so opening This week just to look does not count. UI tests can
    /// lengthen it with `-reading-opening-delay <seconds>`, so a brief look stays brief
    /// on a slow simulator.
    private static let openingDelay: UInt64 = {
        if let value = AppSettings.launchValue("-reading-opening-delay"),
           let seconds = Double(value), seconds > 0 {
            return UInt64(seconds * 1_000_000_000)
        }
        return 20_000_000_000
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .trailing, spacing: 0) {
                    rowsView
                    footer
                }
                .frame(maxWidth: 740)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
            .coordinateSpace(name: "reading")
            .background(Theme.background(scheme))
            .onPreferenceChange(ReadingAnchorKey.self) { anchors in
                noteVisibleParagraph(anchors)
            }
            .onAppear {
                if rows.isEmpty {
                    rows = makeRows()
                }
                restore(using: proxy)
            }
            .onDisappear {
                dwell?.cancel()
            }
        }
        .studyBar(title: navigationTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: portionShareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(L10n.text("a11y.share", settings.language))
            }
        }
    }

    private var navigationTitle: String {
        switch route {
        case .section(let id, _):
            return store.section(id: id)?.name(for: settings.language) ?? ""
        case .weekly(let ids, let titleHe, let titleEn, _):
            let title = settings.language == .he ? titleHe : titleEn
            return title.isEmpty ? store.title(for: ids, language: settings.language) : title
        }
    }

    @ViewBuilder
    private var rowsView: some View {
        if rows.isEmpty {
            Text(L10n.text("reading.empty", settings.language))
                .font(Theme.menuFont(settings.language))
                .foregroundStyle(Theme.secondary(scheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            ForEach(rows) { row in
                switch row {
                case .header(let sectionID):
                    if let section = store.section(id: sectionID) {
                        Text(section.name(for: settings.language))
                            .font(Theme.menuFont(settings.language))
                            .foregroundStyle(Theme.emphasis(scheme))
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.top, 26)
                            .padding(.bottom, 10)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("reading.header.\(sectionID)")
                    }
                case .citation(_, let citation):
                    citationRow(citation)
                case .paragraph(let paragraph):
                    paragraphRow(paragraph)
                case .redirect(_, let targetID):
                    redirectRow(targetID)
                }
            }
        }
    }

    private func citationRow(_ citation: VerseCitation) -> some View {
        Text(store.citationTitle(citation, language: settings.language))
            .font(settings.language == .he ? .custom(Theme.hebrewFamily, size: 16, relativeTo: .subheadline).weight(.semibold) : .subheadline.weight(.semibold))
            .foregroundStyle(Theme.emphasis(scheme))
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(.top, 22)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func redirectRow(_ targetID: Int) -> some View {
        let name = store.section(id: targetID)?.name(for: settings.language) ?? ""
        return NavigationLink(value: ReadingRoute.section(id: targetID, scrollTo: nil)) {
            Label(String(format: L10n.text("reading.redirect", settings.language), name), systemImage: "book")
                .font(settings.language == .he ? .custom(Theme.hebrewFamily, size: 18, relativeTo: .body) : .body)
                .foregroundStyle(Theme.emphasis(scheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reading.redirect.\(targetID)")
        .overlay(alignment: .bottom) { divider }
    }

    private func paragraphRow(_ paragraph: Paragraph) -> some View {
        let spoken = HebrewText.plain(paragraph.body)
        let saved = library.isFavourite(paragraph.id)
        return HStack(alignment: .top, spacing: 10) {
            Button {
                library.toggleFavourite(paragraph.id)
            } label: {
                Image(systemName: saved ? "star.fill" : "star")
                    .font(.body)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    // Apple's minimum touch target is 44 by 44 points. Widen the tappable
                    // area without moving the star or the text beside it.
                    .contentShape(Rectangle().inset(by: -6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text(saved ? "a11y.removeFavourite" : "a11y.addFavourite", settings.language))

            Text(HebrewText.attributed(
                paragraph.body,
                size: settings.textSize,
                textColor: Theme.text(scheme),
                emphasisColor: Theme.emphasis(scheme)
            ))
            .lineSpacing(settings.textSize * 0.38)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .rightToLeft)
            .accessibilityLabel(spoken)
            .hebrewSpeech()
        }
        .environment(\.layoutDirection, .rightToLeft)
        .padding(.vertical, 12)
        .id(paragraph.id)
        .overlay(alignment: .bottom) { divider }
        .background(anchor(for: paragraph.id))
        .contextMenu {
            Button {
                library.toggleFavourite(paragraph.id)
            } label: {
                Label(
                    L10n.text(saved ? "a11y.removeFavourite" : "a11y.addFavourite", settings.language),
                    systemImage: saved ? "star.slash" : "star"
                )
            }
            Button {
                UIPasteboard.general.string = passageShareText(paragraph)
            } label: {
                Label(L10n.text("action.copy", settings.language), systemImage: "doc.on.doc")
            }
            ShareLink(item: passageShareText(paragraph)) {
                Label(L10n.text("action.sharePassage", settings.language), systemImage: "square.and.arrow.up")
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.divider(scheme))
            .frame(height: 0.5)
    }

    private var footer: some View {
        Text(L10n.text("reading.footer", settings.language))
            .font(.footnote)
            .foregroundStyle(Theme.secondary(scheme))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
    }

    /// Only a real read replaces the saved place (Resume and History): a paragraph that
    /// stays at the top for a while. Opening a screen to look, or flicking through it,
    /// does not. Leaving the screen first cancels the pending save.
    private func noteVisibleParagraph(_ anchors: [ReadingAnchor]) {
        guard allowTracking else { return }
        let nearTop = anchors.filter { $0.minY >= -8 && $0.minY < 140 }
        guard let pick = nearTop.min(by: { $0.minY < $1.minY }), pick.id != topID else { return }
        topID = pick.id
        if initialTopID == nil {
            initialTopID = pick.id
        } else if pick.id != initialTopID {
            hasScrolled = true
        }
        let delay = hasScrolled ? Self.settleDelay : Self.openingDelay
        let id = pick.id
        dwell?.cancel()
        dwell = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, id != trackedParagraphID, let paragraph = store.paragraph(id: id) else { return }
            trackedParagraphID = id
            library.note(paragraph)
        }
    }

    private func anchor(for id: Int) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ReadingAnchorKey.self,
                value: [ReadingAnchor(id: id, minY: geo.frame(in: .named("reading")).minY)]
            )
        }
    }

    private func restore(using proxy: ScrollViewProxy) {
        guard let target = route.scrollTarget else {
            allowTracking = true
            return
        }
        // The lazy stack estimates row heights until it builds the target.
        // Scroll once to reach it, then again before tracking starts, so the
        // paragraph sits at the top and the opening dwell stays 20 seconds.
        DispatchQueue.main.async {
            proxy.scrollTo(target, anchor: .top)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                proxy.scrollTo(target, anchor: .top)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                allowTracking = true
            }
        }
    }

    private func makeRows() -> [ReadingRow] {
        switch route {
        case .section(let id, _):
            return sectionRows(id, includeHeader: false)
        case .weekly(let ids, _, _, _):
            return ids.flatMap { sectionRows($0, includeHeader: ids.count > 1) }
        }
    }

    private func sectionRows(_ sectionID: Int, includeHeader: Bool) -> [ReadingRow] {
        let paragraphs = store.paragraphs(sectionID: sectionID)
        guard !paragraphs.isEmpty else { return [] }
        var rows: [ReadingRow] = []
        if includeHeader {
            rows.append(.header(sectionID: sectionID))
        }
        for paragraph in paragraphs {
            if let citation = paragraph.citation {
                rows.append(.citation(paragraphID: paragraph.id, citation: citation))
            }
            rows.append(.paragraph(paragraph))
        }
        if let target = store.section(id: sectionID)?.redirectID {
            rows.append(.redirect(sectionID: sectionID, targetID: target))
        }
        return rows
    }

    private var portionShareText: String {
        String(format: L10n.text("share.portion", settings.language), navigationTitle)
    }

    private func passageShareText(_ paragraph: Paragraph) -> String {
        let name = store.section(id: paragraph.sectionID)?.name(for: settings.language) ?? ""
        return String(
            format: L10n.text("share.passage", settings.language),
            name,
            HebrewText.number(paragraph.index, language: settings.language),
            HebrewText.plain(paragraph.body)
        )
    }
}
