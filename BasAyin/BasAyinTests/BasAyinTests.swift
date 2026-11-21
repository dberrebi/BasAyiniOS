import XCTest
@testable import BasAyin

final class BasAyinTests: XCTestCase {
    func testHebrewNumerals() {
        XCTAssertEqual(HebrewNumerals.string(1), "א׳")
        XCTAssertEqual(HebrewNumerals.string(10), "י׳")
        XCTAssertEqual(HebrewNumerals.string(15), "ט״ו")
        XCTAssertEqual(HebrewNumerals.string(16), "ט״ז")
        XCTAssertEqual(HebrewNumerals.string(37), "ל״ז")
        XCTAssertEqual(HebrewNumerals.string(110), "ק״י")
    }

    func testSearchTermsDropQuoteMarksAndNikud() {
        XCTAssertEqual(HebrewText.searchTerms("חז\"ל"), ["חזל"])
        XCTAssertEqual(HebrewText.searchTerms("חז״ל"), ["חזל"])
        XCTAssertEqual(HebrewText.searchTerms("וַיֵּשֶׁב יעקב"), ["וישב", "יעקב"])
        XCTAssertEqual(HebrewText.ftsQuery("נר חנוכה"), "\"נר\"* \"חנוכה\"*")
        XCTAssertEqual(HebrewText.ftsQuery("light"), "")
        XCTAssertEqual(HebrewText.stripNikud("בְּרֵאשִׁית"), "בראשית")
    }

    func testMarkupAndSnippet() {
        let marked = "<b>וישב</b> יעקב בארץ מגורי אביו"
        XCTAssertEqual(HebrewText.plain(marked), "וישב יעקב בארץ מגורי אביו")
        let long = "<b>הנה</b> " + String(repeating: "מילה ", count: 30) + "כמאמר חז\"ל במדרש " + String(repeating: "סוף ", count: 40)
        let snippet = HebrewText.snippet(long, terms: ["חזל"])
        XCTAssertTrue(snippet.contains("חז\"ל"), snippet)
        XCTAssertTrue(snippet.hasPrefix("…"))
        XCTAssertTrue(snippet.hasSuffix("…"))
        XCTAssertFalse(snippet.contains("<"))
        // A word that only contains the search word in its middle does not count as a match.
        XCTAssertTrue(HebrewText.snippet("<b>אבג</b> לחזל", terms: ["חזל"]).hasPrefix("אבג"))
    }

    @MainActor
    func testSearchMatchesAbbreviationsWithOrWithoutQuoteMarks() throws {
        let store = TextStore()
        XCTAssertNil(store.loadError)
        let plain = store.search("חזל")
        XCTAssertFalse(plain.isEmpty)
        let quoted = store.search("חז\"ל")
        XCTAssertEqual(quoted.map(\.id), plain.map(\.id))
        let first = try XCTUnwrap(plain.first)
        XCTAssertTrue(first.snippet.contains("חז"), first.snippet)
        XCTAssertTrue(store.search("   ").isEmpty)
        XCTAssertTrue(store.search("xyzzy").isEmpty)
        let chanukah = store.search("חנוכה")
        XCTAssertTrue(chanukah.contains { $0.paragraph.sectionID == 10 })
    }

    @MainActor
    func testBundledText() throws {
        let store = TextStore()
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.books.map(\.heName), ["בראשית", "שמות", "ויקרא", "במדבר", "דברים"])
        XCTAssertEqual(store.sections.count, TextStore.expectedSectionCount)

        let genesis = store.sections(in: .book(1))
        XCTAssertEqual(genesis.first?.heName, "בראשית")
        XCTAssertTrue(genesis.contains { $0.heName == "חנוכה" })
        let moadim = store.sections(in: .moadim)
        XCTAssertEqual(moadim.count, 17)
        XCTAssertEqual(moadim.first?.heName, "דרוש לערב ראש השנה")
        XCTAssertEqual(moadim.last?.heName, "שבועות")
        XCTAssertEqual(store.sections(in: .appendix).map(\.enName), ["Likkutim", "Responsa"])

        let opening = try XCTUnwrap(store.paragraph(id: 1_001))
        XCTAssertTrue(HebrewText.plain(opening.body).contains("בראשית ברא"))
        // "בראשית ברא וגו' והארץ היתה…" skips words after וגו', and still opens on Genesis 1:1.
        XCTAssertEqual(opening.citation, VerseCitation(bookID: 1, chapter: 1, verse: 1))
        let vayeshev = try XCTUnwrap(store.paragraph(id: 9_001))
        XCTAssertEqual(vayeshev.citation, VerseCitation(bookID: 1, chapter: 37, verse: 1))
        XCTAssertEqual(store.citationTitle(try XCTUnwrap(vayeshev.citation), language: .he), "בראשית ל״ז, א׳")
        XCTAssertEqual(store.citationTitle(try XCTUnwrap(vayeshev.citation), language: .en), "Genesis 37:1")
        XCTAssertEqual(store.locationTitle(for: vayeshev, language: .he), "וישב · פסקה א׳")

        // The pointer sections lead to the parasha where their derashot are printed.
        XCTAssertEqual(store.section(id: 20)?.redirectID, 25)
        XCTAssertEqual(store.section(id: 25)?.heName, "כי תשא")
        XCTAssertEqual(store.section(id: 26)?.redirectID, 51)
        XCTAssertEqual(store.section(id: 51)?.heName, "חקת")
        XCTAssertNil(store.paragraph(id: 999_999))
    }

    @MainActor
    func testThisWeeksReading() throws {
        let store = TextStore()
        func reading(_ year: Int, _ month: Int, _ day: Int, israel: Bool) -> WeeklyReading? {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
            return date.flatMap { store.currentReading(israel: israel, now: $0) }
        }
        // An ordinary week.
        let vayetzei = try XCTUnwrap(reading(2026, 11, 16, israel: true))
        XCTAssertEqual(vayetzei.sectionIDs, [7])
        XCTAssertEqual(vayetzei.titleHe, "ויצא")
        // Chanukah through Shabbat Miketz.
        let miketz = try XCTUnwrap(reading(2026, 12, 6, israel: false))
        XCTAssertEqual(miketz.sectionIDs, [11, 10])
        XCTAssertEqual(miketz.titleHe, "מקץ · חנוכה")
        XCTAssertEqual(miketz.titleEn, "Miketz · Chanukah")
        // Rosh HaShanah II falls on Sunday; from Monday it is no longer part of the week.
        XCTAssertTrue(try XCTUnwrap(reading(2026, 9, 13, israel: false)).sectionIDs.contains(67))
        let shuvah = try XCTUnwrap(reading(2026, 9, 14, israel: false))
        XCTAssertFalse(shuvah.sectionIDs.contains(67))
        XCTAssertEqual(Array(shuvah.sectionIDs.prefix(3)), [69, 66, 68])
        // Vayakhel-Pekudei with Shabbat HaChodesh.
        XCTAssertEqual(try XCTUnwrap(reading(2026, 3, 9, israel: false)).sectionIDs, [27, 28, 29])
        // Simchat Torah: Sunday in the Diaspora, the Shabbat before in Israel.
        XCTAssertEqual(try XCTUnwrap(reading(2026, 10, 4, israel: false)).sectionIDs, [1, 71])
        XCTAssertEqual(try XCTUnwrap(reading(2026, 10, 4, israel: true)).sectionIDs, [1])
        // Shabbat Chol HaMoed Pesach has no parasha: the festival's sections, in the order of the edition.
        XCTAssertEqual(try XCTUnwrap(reading(2026, 4, 4, israel: true)).sectionIDs, [33, 34, 38])
    }

    func testIsraelCalendarFollowsRegion() {
        XCTAssertTrue(AppSettings.usesIsraelCalendar(regionCode: "IL"))
        XCTAssertFalse(AppSettings.usesIsraelCalendar(regionCode: "US"))
        XCTAssertFalse(AppSettings.usesIsraelCalendar(regionCode: nil))
    }

    @MainActor
    func testHistoryKeepsOneRowPerSection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = TextStore()
        let library = UserLibrary(storageURL: directory.appendingPathComponent("library.json"))
        let first = try XCTUnwrap(store.paragraphs(sectionID: 1).first)
        let later = try XCTUnwrap(store.paragraphs(sectionID: 1).dropFirst(8).first)
        let other = try XCTUnwrap(store.paragraphs(sectionID: 2).first)
        library.note(first)
        library.note(later)
        XCTAssertEqual(library.history.count, 1)
        XCTAssertEqual(library.history[0].paragraphID, later.id)
        library.note(other)
        XCTAssertEqual(library.history.count, 2)
        XCTAssertEqual(library.history[0].sectionID, 2)
    }

    @MainActor
    func testReadingASectionAgainMovesItToTheTop() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = TextStore()
        let library = UserLibrary(storageURL: directory.appendingPathComponent("library.json"))
        let first = try XCTUnwrap(store.paragraphs(sectionID: 1).first)
        let other = try XCTUnwrap(store.paragraphs(sectionID: 2).first)
        library.note(first)
        library.note(other)
        XCTAssertEqual(library.history.map(\.sectionID), [2, 1])
        // Back to Bereshit at the same paragraph as before.
        library.note(first)
        XCTAssertEqual(library.history.map(\.sectionID), [1, 2])
        XCTAssertEqual(library.lastParagraphID, first.id)
    }

    @MainActor
    func testFlushHasWrittenTheFileWhenItReturns() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("library.json")
        let store = TextStore()
        let paragraph = try XCTUnwrap(store.paragraphs(sectionID: 1).first)
        let library = UserLibrary(storageURL: url)
        library.toggleFavourite(paragraph.id)
        library.note(paragraph)
        library.flush()
        let reopened = UserLibrary(storageURL: url)
        XCTAssertEqual(reopened.favouriteIDs, [paragraph.id])
        XCTAssertEqual(reopened.history.first?.paragraphID, paragraph.id)
    }

    @MainActor
    func testUnreadableLibraryIsBackedUp() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("library.json")
        try Data("not json".utf8).write(to: url)
        let library = UserLibrary(storageURL: url)
        XCTAssertTrue(library.history.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(names.contains { $0.contains("corrupt-") })
    }
}
