import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case he
    case en

    var id: String { rawValue }

    var localeIdentifier: String { self == .he ? "he" : "en" }
}

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

struct Book: Identifiable, Hashable {
    let id: Int
    let heName: String
    let enName: String

    func name(for language: AppLanguage) -> String {
        language == .he ? heName : enName
    }
}

/// How a section of the edition is used: a weekly parasha, a section for two parshiyot read
/// together, a special Shabbat, a festival, or the likkutim and responsa at the end.
enum SectionKind: String {
    case parasha
    case combined
    case special
    case moed
    case appendix
}

/// One section of Bas Ayin, as the edition divides it (נח, חנוכה, דרוש לפרשת שקלים…).
struct TextSection: Identifiable, Hashable {
    let id: Int
    let bookID: Int?
    let heName: String
    let enName: String
    let kind: SectionKind
    let sortOrder: Int
    /// Position in the festivals list, counted from Tishrei.
    let moedOrder: Int?
    /// A one-line section that says where its derashot are printed (Shekalim, Parah).
    let redirectID: Int?

    func name(for language: AppLanguage) -> String {
        language == .he ? heName : enName
    }
}

/// The verse a paragraph opens on, when it opens a derush by quoting and citing it.
struct VerseCitation: Hashable {
    let bookID: Int
    let chapter: Int
    let verse: Int
}

struct Paragraph: Identifiable, Hashable {
    /// section × 1000 + index. Stable across launches, so favourites and the resume place keep.
    let id: Int
    let sectionID: Int
    let index: Int
    let body: String
    let citation: VerseCitation?
}

/// The reading for one Shabbat: its parasha and special Shabbat, plus any festival
/// whose day falls between today and that Shabbat.
struct WeeklyReading: Identifiable, Hashable {
    let date: String
    let israel: Bool
    let titleHe: String
    let titleEn: String
    let sectionIDs: [Int]

    var id: String { "\(date)#\(israel ? 1 : 0)" }

    func title(for language: AppLanguage) -> String {
        language == .he ? titleHe : titleEn
    }
}

struct FestivalDay: Hashable {
    let date: String
    let israel: Bool
    let label: String
    let titleHe: String
    let titleEn: String
    let sectionIDs: [Int]
}

struct SearchHit: Identifiable, Hashable {
    let paragraph: Paragraph
    let snippet: String

    var id: Int { paragraph.id }
}

/// The lists of sections the home screen opens.
enum SectionGroup: Hashable {
    case book(Int)
    case moadim
    case appendix
}

enum SidebarItem: Hashable {
    case resume
    case history
    case weekly
    case search
    case sections(SectionGroup)
    case settings
    case help
    case about
    case favourites

    var accessibilityID: String {
        switch self {
        case .resume: return "home.resume"
        case .history: return "home.history"
        case .weekly: return "home.weekly"
        case .search: return "home.search"
        case .sections(.book(let id)): return "home.book.\(id)"
        case .sections(.moadim): return "home.moadim"
        case .sections(.appendix): return "home.appendix"
        case .settings: return "home.settings"
        case .help: return "home.help"
        case .about: return "home.about"
        case .favourites: return "home.favourites"
        }
    }
}

enum ReadingRoute: Hashable {
    case section(id: Int, scrollTo: Int?)
    case weekly(ids: [Int], titleHe: String, titleEn: String, scrollTo: Int?)

    var scrollTarget: Int? {
        switch self {
        case .section(_, let scrollTo), .weekly(_, _, _, let scrollTo):
            return scrollTo
        }
    }
}
