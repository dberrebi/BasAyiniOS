import Foundation
import Observation
import SQLite3

@MainActor
@Observable
final class TextStore {
    @ObservationIgnored private var database: OpaquePointer?
    private(set) var books: [Book] = []
    private(set) var sections: [TextSection] = []
    private(set) var weekly: [WeeklyReading] = []
    private(set) var festivalDays: [FestivalDay] = []
    private(set) var meta: [String: String] = [:]
    private(set) var loadError: String?

    @ObservationIgnored private var paragraphsBySection: [Int: [Paragraph]] = [:]
    @ObservationIgnored private var readingCacheKey: String?
    @ObservationIgnored private var readingCacheValue: WeeklyReading?

    /// The number of sections in the bundled edition.
    static let expectedSectionCount = 74

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init() {
        open()
    }

    var yearStart: String { meta["year_start"] ?? "2025" }
    var yearEnd: String { meta["year_end"] ?? "2045" }

    func book(id: Int) -> Book? {
        books.first { $0.id == id }
    }

    func section(id: Int) -> TextSection? {
        sections.first { $0.id == id }
    }

    /// The sections of one book, in the order of the edition, festivals included where they are printed.
    func sections(in group: SectionGroup) -> [TextSection] {
        switch group {
        case .book(let bookID):
            return sections.filter { $0.bookID == bookID && $0.kind != .appendix }.sorted { $0.sortOrder < $1.sortOrder }
        case .moadim:
            return sections.filter { $0.moedOrder != nil }.sorted { ($0.moedOrder ?? 0) < ($1.moedOrder ?? 0) }
        case .appendix:
            return sections.filter { $0.kind == .appendix }.sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    func groupTitle(_ group: SectionGroup, language: AppLanguage) -> String {
        switch group {
        case .book(let id):
            return book(id: id)?.name(for: language) ?? ""
        case .moadim:
            return L10n.text("home.moadim", language)
        case .appendix:
            return L10n.text("home.appendix", language)
        }
    }

    func paragraphs(sectionID: Int) -> [Paragraph] {
        if let cached = paragraphsBySection[sectionID] { return cached }
        let rows: [Paragraph] = query("""
            SELECT id, section_id, paragraph_index, body, cite_book_id, cite_chapter, cite_verse
            FROM paragraphs
            WHERE section_id = \(sectionID)
            ORDER BY paragraph_index
            """) { statement in
            var citation: VerseCitation?
            if sqlite3_column_type(statement, 4) != SQLITE_NULL {
                citation = VerseCitation(
                    bookID: Int(sqlite3_column_int(statement, 4)),
                    chapter: Int(sqlite3_column_int(statement, 5)),
                    verse: Int(sqlite3_column_int(statement, 6))
                )
            }
            return Paragraph(
                id: Int(sqlite3_column_int64(statement, 0)),
                sectionID: Int(sqlite3_column_int(statement, 1)),
                index: Int(sqlite3_column_int(statement, 2)),
                body: columnText(statement, 3),
                citation: citation
            )
        }
        paragraphsBySection[sectionID] = rows
        return rows
    }

    func paragraph(id: Int) -> Paragraph? {
        let sectionID = id / 1000
        guard section(id: sectionID) != nil else { return nil }
        return paragraphs(sectionID: sectionID).first { $0.id == id }
    }

    func search(_ rawQuery: String, limit: Int = 60) -> [SearchHit] {
        let terms = HebrewText.searchTerms(rawQuery)
        let match = HebrewText.ftsQuery(terms)
        guard !match.isEmpty, let database else { return [] }
        var statement: OpaquePointer?
        let sql = """
            SELECT paragraph_id
            FROM paragraphs_fts
            WHERE paragraphs_fts MATCH ?
            ORDER BY rank
            LIMIT ?
            """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let prepared = statement else {
            sqlite3_finalize(statement)
            return []
        }
        defer { sqlite3_finalize(prepared) }
        let encoded = Array(match.utf8) + [0]
        var ids: [Int] = []
        encoded.withUnsafeBufferPointer { buffer in
            // The pointer stays valid through sqlite3_step. A nil destructor keeps that buffer.
            sqlite3_bind_text(prepared, 1, buffer.baseAddress, -1, nil)
            sqlite3_bind_int(prepared, 2, Int32(limit))
            while sqlite3_step(prepared) == SQLITE_ROW {
                ids.append(Int(sqlite3_column_int64(prepared, 0)))
            }
        }
        return ids.compactMap { id in
            guard let found = paragraph(id: id) else { return nil }
            return SearchHit(paragraph: found, snippet: HebrewText.snippet(found.body, terms: terms))
        }
    }

    func title(for sectionIDs: [Int], language: AppLanguage) -> String {
        sectionIDs.compactMap { section(id: $0)?.name(for: language) }.joined(separator: " · ")
    }

    func locationTitle(for paragraph: Paragraph, language: AppLanguage) -> String {
        let name = section(id: paragraph.sectionID)?.name(for: language) ?? ""
        let place = String(
            format: L10n.text("reading.paragraph", language),
            HebrewText.number(paragraph.index, language: language)
        )
        return name.isEmpty ? place : "\(name) · \(place)"
    }

    /// "בראשית ל״ז, א׳" or "Genesis 37:1".
    func citationTitle(_ citation: VerseCitation, language: AppLanguage) -> String {
        String(
            format: L10n.text("reading.citation", language),
            book(id: citation.bookID)?.name(for: language) ?? "",
            HebrewText.number(citation.chapter, language: language),
            HebrewText.number(citation.verse, language: language)
        )
    }

    func formattedDate(_ iso: String, language: AppLanguage) -> String {
        guard let date = date(fromISO: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// "This week": the coming Shabbat (today, on Shabbat) with its parasha and any special
    /// Shabbat, then each festival with a day, or its eve, from today until that Shabbat.
    /// A festival that ended earlier in the week is not shown again.
    func currentReading(israel: Bool, now: Date = Date()) -> WeeklyReading? {
        let todayISO = isoDay(now)
        let key = "\(todayISO)#\(israel ? 1 : 0)"
        if key == readingCacheKey {
            return readingCacheValue
        }
        let value = resolveReading(israel: israel, todayISO: todayISO)
        readingCacheKey = key
        readingCacheValue = value
        return value
    }

    private func resolveReading(israel: Bool, todayISO: String) -> WeeklyReading? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let today = date(fromISO: todayISO) else { return nil }
        // weekday: 1 is Sunday, 7 is Shabbat.
        let weekday = calendar.component(.weekday, from: today)
        guard let shabbat = calendar.date(byAdding: .day, value: 7 - weekday, to: today) else { return nil }
        let shabbatISO = isoDay(shabbat)
        guard let row = weekly.first(where: { $0.israel == israel && $0.date == shabbatISO }) else { return nil }

        var ids = row.sectionIDs
        var titlesHe = row.titleHe.components(separatedBy: " · ").filter { !$0.isEmpty }
        var titlesEn = row.titleEn.components(separatedBy: " · ").filter { !$0.isEmpty }
        let days = festivalDays.filter { $0.israel == israel && $0.date >= todayISO && $0.date <= shabbatISO }
        var labels: [String] = []
        var idsByLabel: [String: Set<Int>] = [:]
        for day in days {
            if !labels.contains(day.label) {
                labels.append(day.label)
                if !titlesHe.contains(day.titleHe) {
                    titlesHe.append(day.titleHe)
                    titlesEn.append(day.titleEn)
                }
            }
            idsByLabel[day.label, default: []].formUnion(day.sectionIDs)
        }
        for label in labels {
            // Within one festival, the sections keep the order of the edition.
            for id in (idsByLabel[label] ?? []).sorted() where !ids.contains(id) {
                ids.append(id)
            }
        }
        guard !ids.isEmpty else { return nil }
        return WeeklyReading(
            date: shabbatISO,
            israel: israel,
            titleHe: titlesHe.joined(separator: " · "),
            titleEn: titlesEn.joined(separator: " · "),
            sectionIDs: ids
        )
    }

    private func isoDay(_ date: Date) -> String {
        Self.isoFormatter.timeZone = .current
        return Self.isoFormatter.string(from: date)
    }

    private func date(fromISO iso: String) -> Date? {
        Self.isoFormatter.timeZone = .current
        return Self.isoFormatter.date(from: iso)
    }

    func readingCoversToday(_ now: Date = Date()) -> Bool {
        guard
            let start = Int(yearStart),
            let end = Int(yearEnd)
        else { return true }
        let year = Calendar(identifier: .gregorian).component(.year, from: now)
        return year >= start && year <= end
    }

    private func open() {
        guard let url = Bundle.main.url(forResource: "bas_ayin", withExtension: "sqlite") else {
            loadError = "missing"
            return
        }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            loadError = "open"
            return
        }
        database = handle
        loadBooks()
        loadSections()
        loadWeekly()
        loadFestivalDays()
        loadMeta()
        if books.count != 5 || sections.count != Self.expectedSectionCount {
            loadError = "incomplete"
        }
    }

    private func loadBooks() {
        books = query("SELECT id, he_name, en_name FROM books ORDER BY sort_order") { statement in
            Book(
                id: Int(sqlite3_column_int(statement, 0)),
                heName: columnText(statement, 1),
                enName: columnText(statement, 2)
            )
        }
    }

    private func loadSections() {
        sections = query("""
            SELECT id, book_id, he_name, en_name, kind, sort_order, moed_order, redirect_id
            FROM sections
            ORDER BY sort_order
            """) { statement in
            TextSection(
                id: Int(sqlite3_column_int(statement, 0)),
                bookID: optionalInt(statement, 1),
                heName: columnText(statement, 2),
                enName: columnText(statement, 3),
                kind: SectionKind(rawValue: columnText(statement, 4)) ?? .parasha,
                sortOrder: Int(sqlite3_column_int(statement, 5)),
                moedOrder: optionalInt(statement, 6),
                redirectID: optionalInt(statement, 7)
            )
        }
    }

    private func loadWeekly() {
        weekly = query("""
            SELECT gregorian_date, israel, title_he, title_en, section_ids
            FROM weekly
            ORDER BY gregorian_date
            """) { statement in
            WeeklyReading(
                date: columnText(statement, 0),
                israel: sqlite3_column_int(statement, 1) == 1,
                titleHe: columnText(statement, 2),
                titleEn: columnText(statement, 3),
                sectionIDs: idList(columnText(statement, 4))
            )
        }
    }

    private func loadFestivalDays() {
        festivalDays = query("""
            SELECT gregorian_date, israel, label, title_he, title_en, section_ids
            FROM festival_days
            ORDER BY gregorian_date
            """) { statement in
            FestivalDay(
                date: columnText(statement, 0),
                israel: sqlite3_column_int(statement, 1) == 1,
                label: columnText(statement, 2),
                titleHe: columnText(statement, 3),
                titleEn: columnText(statement, 4),
                sectionIDs: idList(columnText(statement, 5))
            )
        }
    }

    private func loadMeta() {
        let rows: [(String, String)] = query("SELECT key, value FROM meta") { statement in
            (columnText(statement, 0), columnText(statement, 1))
        }
        meta = Dictionary(uniqueKeysWithValues: rows)
    }

    private func idList(_ text: String) -> [Int] {
        text.split(separator: ",").compactMap { Int($0) }
    }

    private func query<T>(_ sql: String, map: (OpaquePointer) -> T) -> [T] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let prepared = statement else {
            sqlite3_finalize(statement)
            return []
        }
        defer { sqlite3_finalize(prepared) }
        var rows: [T] = []
        while sqlite3_step(prepared) == SQLITE_ROW {
            rows.append(map(prepared))
        }
        return rows
    }

    private func optionalInt(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, index))
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self))
    }
}
