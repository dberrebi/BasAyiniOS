#!/usr/bin/env python3
"""Build the offline Bas Ayin (בת עין) database.

Downloads:
  * Sefaria's Hebrew version of Bat Ayin titled exactly "Jerusalem, 2001"
    (licence CC-BY-NC, which Sefaria links to CC BY-NC 4.0). It is the only
    Hebrew version on Sefaria. The text is unpointed.
  * The Sefaria index of Bat Ayin, to check the order and Hebrew names of
    its 74 sections.
  * The five books of the Torah, "Tanach with Text Only" (Public Domain), used
    only while building: a paragraph that opens by quoting a verse and citing
    it gets a heading with that citation, and the quotation is checked against
    the verse. The Torah text is not bundled.
  * A weekly table from the Hebcal REST API (CC BY 4.0), Israel (i=on) and
    Diaspora (i=off): the Shabbat parasha, the special Shabbatot (Shekalim,
    Zachor, Parah, HaChodesh, HaGadol, Shuva) and the festivals that Bas Ayin
    has derashot for (Rosh HaShanah, Yom Kippur, Sukkot, Simchat Torah,
    Chanukah, Purim, Pesach, Shavuot).

No GPL code is used. The script depends only on the Python standard library.

The text stored in the database is Hebrew only. English fields are names of
books and sections used by the interface, never a translation. Sefaria also
has a partial English community translation; it is never requested.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from html import unescape
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "BasAyin" / "BasAyin" / "Resources" / "bas_ayin.sqlite"
DEFAULT_MANIFEST = ROOT / "data" / "manifest.json"
CACHE_DIR = Path(__file__).resolve().parent / ".cache"

SEFARIA_TITLE = "Bat Ayin"
TEXT_VERSION = "Jerusalem, 2001"  # exact
TEXT_LICENSE = "CC-BY-NC"
TEXT_LICENSE_URL = "https://creativecommons.org/licenses/by-nc/4.0/"
TEXT_SOURCE = "https://www.sefaria.org/Bat_Ayin"

# Used only at build time, to check that a paragraph really opens by quoting the
# verse it cites. Not bundled.
TORAH_CHECK_VERSION = "Tanach with Text Only"
TORAH_CHECK_LICENSE = "Public Domain"

USER_AGENT = "BasAyinDataBuilder/1.0 (offline study app; +https://www.sefaria.org)"

DEFAULT_YEAR_START = 2025
DEFAULT_YEAR_END = 2045

# The five books of the Torah. Sections of Bas Ayin belong to the book in
# whose part of the edition they are printed. Likkutim and the responsa have
# no book.
BOOKS = [
    (1, "Genesis", "בראשית", "Genesis"),
    (2, "Exodus", "שמות", "Exodus"),
    (3, "Leviticus", "ויקרא", "Leviticus"),
    (4, "Numbers", "במדבר", "Numbers"),
    (5, "Deuteronomy", "דברים", "Deuteronomy"),
]

# The 54 parshiyot, for the weekly table and its titles.
# (key, hebrew, english)
PARASHOT = [
    ("Bereshit", "בראשית", "Bereshit"),
    ("Noach", "נח", "Noach"),
    ("Lech Lecha", "לך לך", "Lech Lecha"),
    ("Vayera", "וירא", "Vayera"),
    ("Chayei Sara", "חיי שרה", "Chayei Sara"),
    ("Toldot", "תולדות", "Toldot"),
    ("Vayetzei", "ויצא", "Vayetzei"),
    ("Vayishlach", "וישלח", "Vayishlach"),
    ("Vayeshev", "וישב", "Vayeshev"),
    ("Miketz", "מקץ", "Miketz"),
    ("Vayigash", "ויגש", "Vayigash"),
    ("Vayechi", "ויחי", "Vayechi"),
    ("Shemot", "שמות", "Shemot"),
    ("Vaera", "וארא", "Vaera"),
    ("Bo", "בא", "Bo"),
    ("Beshalach", "בשלח", "Beshalach"),
    ("Yitro", "יתרו", "Yitro"),
    ("Mishpatim", "משפטים", "Mishpatim"),
    ("Terumah", "תרומה", "Terumah"),
    ("Tetzaveh", "תצוה", "Tetzaveh"),
    ("Ki Tisa", "כי תשא", "Ki Tisa"),
    ("Vayakhel", "ויקהל", "Vayakhel"),
    ("Pekudei", "פקודי", "Pekudei"),
    ("Vayikra", "ויקרא", "Vayikra"),
    ("Tzav", "צו", "Tzav"),
    ("Shmini", "שמיני", "Shmini"),
    ("Tazria", "תזריע", "Tazria"),
    ("Metzora", "מצורע", "Metzora"),
    ("Achrei Mot", "אחרי מות", "Achrei Mot"),
    ("Kedoshim", "קדושים", "Kedoshim"),
    ("Emor", "אמור", "Emor"),
    ("Behar", "בהר", "Behar"),
    ("Bechukotai", "בחוקותי", "Bechukotai"),
    ("Bamidbar", "במדבר", "Bamidbar"),
    ("Nasso", "נשא", "Nasso"),
    ("Beha'alotcha", "בהעלותך", "Beha'alotcha"),
    ("Sh'lach", "שלח", "Sh'lach"),
    ("Korach", "קרח", "Korach"),
    ("Chukat", "חקת", "Chukat"),
    ("Balak", "בלק", "Balak"),
    ("Pinchas", "פנחס", "Pinchas"),
    ("Matot", "מטות", "Matot"),
    ("Masei", "מסעי", "Masei"),
    ("Devarim", "דברים", "Devarim"),
    ("Vaetchanan", "ואתחנן", "Vaetchanan"),
    ("Eikev", "עקב", "Eikev"),
    ("Re'eh", "ראה", "Re'eh"),
    ("Shoftim", "שופטים", "Shoftim"),
    ("Ki Teitzei", "כי תצא", "Ki Teitzei"),
    ("Ki Tavo", "כי תבוא", "Ki Tavo"),
    ("Nitzavim", "נצבים", "Nitzavim"),
    ("Vayeilech", "וילך", "Vayeilech"),
    ("Ha'Azinu", "האזינו", "Ha'Azinu"),
    ("V'Zot HaBerachah", "וזאת הברכה", "V'Zot HaBerachah"),
]
PARASHA_KEYS = [row[0] for row in PARASHOT]
PARASHA_NAMES = {row[0]: (row[1], row[2]) for row in PARASHOT}

# Short labels for the week's title.
LABELS = {
    "shekalim": ("שבת שקלים", "Shabbat Shekalim"),
    "zachor": ("שבת זכור", "Shabbat Zachor"),
    "parah": ("שבת פרה", "Shabbat Parah"),
    "hachodesh": ("שבת החודש", "Shabbat HaChodesh"),
    "hagadol": ("שבת הגדול", "Shabbat HaGadol"),
    "shuva": ("שבת שובה", "Shabbat Shuvah"),
    "rosh_hashanah": ("ראש השנה", "Rosh HaShanah"),
    "yom_kippur": ("יום כיפור", "Yom Kippur"),
    "sukkot": ("סוכות", "Sukkot"),
    "shemini_atzeret": ("שמיני עצרת", "Shemini Atzeret"),
    "simchat_torah": ("שמחת תורה", "Simchat Torah"),
    "chanukah": ("חנוכה", "Chanukah"),
    "purim": ("פורים", "Purim"),
    "pesach": ("פסח", "Pesach"),
    "shavuot": ("שבועות", "Shavuot"),
}


@dataclass(frozen=True)
class SectionDef:
    key: str  # Sefaria node key
    he: str  # Sefaria primary Hebrew title, checked against the index
    en: str  # English name for the interface
    book: int | None
    kind: str  # parasha, combined, special, moed, appendix
    covers: tuple[str, ...] = ()  # parshiyot whose week this section belongs to
    redirect: str | None = None  # a one-line pointer section: where its derashot are
    moed_order: int | None = None  # order in the festivals list, from Tishrei


def P(key: str, he: str, book: int, en: str | None = None) -> SectionDef:
    return SectionDef(key, he, en or key, book, "parasha", (key,))


# The 74 sections, in the order of the edition (and of Sefaria's schema).
# Stable ids are this order, starting at 1.
SECTION_DEFS: list[SectionDef] = [
    P("Bereshit", "בראשית", 1),
    P("Noach", "נח", 1),
    P("Lech Lecha", "לך לך", 1),
    P("Vayera", "וירא", 1),
    P("Chayei Sara", "חיי שרה", 1),
    P("Toldot", "תולדות", 1),
    P("Vayetzei", "ויצא", 1),
    P("Vayishlach", "וישלח", 1),
    P("Vayeshev", "וישב", 1),
    SectionDef("Chanukah", "חנוכה", "Chanukah", 1, "moed", moed_order=7),
    P("Miketz", "מקץ", 1),
    P("Vayigash", "ויגש", 1),
    P("Vayechi", "ויחי", 1),
    P("Shemot", "שמות", 2),
    P("Vaera", "וארא", 2),
    P("Bo", "בא", 2),
    P("Beshalach", "בשלח", 2),
    P("Yitro", "יתרו", 2),
    P("Mishpatim", "משפטים", 2),
    SectionDef(
        "Parashat Shekalim", "דרוש לפרשת שקלים", "Parashat Shekalim", 2, "special",
        redirect="Ki Tisa", moed_order=8,
    ),
    P("Terumah", "תרומה", 2),
    P("Tetzaveh", "תצוה", 2),
    SectionDef("Parashat Zakhor", "דרושים לפרשת זכור", "Parashat Zachor", 2, "special", moed_order=9),
    SectionDef("Purim", "פורים", "Purim", 2, "moed", moed_order=10),
    P("Ki Tisa", "כי תשא", 2),
    SectionDef(
        "Parashat Parah", "פרשת פרה", "Parashat Parah", 2, "special",
        redirect="Chukat", moed_order=11,
    ),
    P("Vayakhel", "ויקהל", 2),
    SectionDef("Vayakhel Pekudei", "ויקהל פקודי", "Vayakhel-Pekudei", 2, "combined", ("Vayakhel", "Pekudei")),
    SectionDef("Parashat HaChodesh", "דרוש לפרשת החדש", "Parashat HaChodesh", 2, "special", moed_order=12),
    P("Vayikra", "ויקרא", 3),
    P("Tzav", "צו", 3),
    SectionDef("Shabbat HaGadol", "דרושים לשבת הגדול", "Shabbat HaGadol", 3, "special", moed_order=13),
    SectionDef("Pesach I", "פסח - חג ראשון", "Pesach: First Day", 3, "moed", moed_order=14),
    SectionDef(
        "Shabbat Chol HaMoed Pesach", 'דרושים לשבת חוה"מ פסח', "Shabbat Chol HaMoed Pesach", 3, "moed",
        moed_order=15,
    ),
    P("Shmini", "שמיני", 3),
    P("Tazria", "תזריע", 3),
    P("Metzora", "מצורע", 3),
    SectionDef("Pesach II", "דרוש לפסח", "Pesach", 3, "moed", moed_order=16),
    P("Achrei Mot", "אחרי מות", 3),
    P("Kedoshim", "קדושים", 3),
    P("Emor", "אמור", 3),
    P("Behar", "בהר", 3),
    SectionDef(
        "Behar Bechukotai", "דרוש לפרשת בהר ובחקותי", "Behar-Bechukotai", 3, "combined",
        ("Behar", "Bechukotai"),
    ),
    P("Bechukotai", "בחוקתי", 3),
    P("Bamidbar", "במדבר", 4),
    SectionDef("Shavuot", "שבועות", "Shavuot", 4, "moed", moed_order=17),
    P("Nasso", "נשא", 4),
    P("Beha'alotcha", "בהעלותך", 4),
    P("Sh'lach", "שלח", 4),
    P("Korach", "קרח", 4),
    P("Chukat", "חקת", 4),
    P("Balak", "בלק", 4),
    P("Pinchas", "פנחס", 4),
    SectionDef("Matot Masei", "מטות מסעי", "Matot-Masei", 4, "combined", ("Matot", "Masei")),
    P("Masei", "מסעי", 4),
    P("Devarim", "דברים", 5),
    P("Vaetchanan", "ואתחנן", 5),
    P("Eikev", "עקב", 5),
    P("Re'eh", "ראה", 5),
    P("Shoftim", "שופטים", 5),
    P("Ki Teitzei", "כי תצא", 5),
    P("Ki Tavo", "כי תבוא", 5),
    P("Nitzavim", "נצבים", 5),
    SectionDef("Erev Rosh HaShanah", "דרוש לערב ראש השנה", "Erev Rosh HaShanah", 5, "moed", moed_order=1),
    P("Vayeilech", "וילך", 5),
    SectionDef("Shabbat Shuvah I", "דרוש לשבת תשובה", "Shabbat Shuvah I", 5, "special", moed_order=3),
    SectionDef("Rosh HaShanah", "דרוש לראש השנה", "Rosh HaShanah", 5, "moed", moed_order=2),
    SectionDef("Shabbat Shuvah II", "דרושים לשבת תשובה", "Shabbat Shuvah II", 5, "special", moed_order=4),
    P("Ha'Azinu", "האזינו", 5),
    SectionDef("Yom Kippur", "יום כיפור", "Yom Kippur", 5, "moed", moed_order=5),
    P("V'Zot HaBerachah", "וזאת הברכה", 5),
    SectionDef("Sukkot", "סוכות", "Sukkot", 5, "moed", moed_order=6),
    SectionDef("Likkutim", "לקוטים", "Likkutim", None, "appendix"),
    SectionDef("Responsa", 'שו"ת', "Responsa", None, "appendix"),
]
SECTION_IDS = {section.key: index for index, section in enumerate(SECTION_DEFS, start=1)}

# Hebcal special-Shabbat titles -> (label, section keys).
SPECIAL_SHABBAT = {
    "shabbatshekalim": ("shekalim", ["Parashat Shekalim"]),
    "shabbatzachor": ("zachor", ["Parashat Zakhor"]),
    "shabbatzakhor": ("zachor", ["Parashat Zakhor"]),
    "shabbatparah": ("parah", ["Parashat Parah"]),
    "shabbathachodesh": ("hachodesh", ["Parashat HaChodesh"]),
    "shabbathachodeshh": ("hachodesh", ["Parashat HaChodesh"]),
    "shabbathagadol": ("hagadol", ["Shabbat HaGadol"]),
    "shabbatshuva": ("shuva", ["Shabbat Shuvah I", "Shabbat Shuvah II"]),
    "shabbatshuvah": ("shuva", ["Shabbat Shuvah I", "Shabbat Shuvah II"]),
}

# Hebcal holiday titles (by prefix of the letters-only key) -> (label, section keys).
# Each day of a festival, and its eve, is stored; see FestivalDay.
HOLIDAY_PREFIXES = [
    ("erevroshhashana", "rosh_hashanah", ["Erev Rosh HaShanah", "Rosh HaShanah"]),
    ("roshhashana", "rosh_hashanah", ["Erev Rosh HaShanah", "Rosh HaShanah"]),
    ("erevyomkippur", "yom_kippur", ["Yom Kippur"]),
    ("yomkippur", "yom_kippur", ["Yom Kippur"]),
    ("erevsukkot", "sukkot", ["Sukkot"]),
    ("sukkot", "sukkot", ["Sukkot"]),
    ("simchattorah", "simchat_torah", ["V'Zot HaBerachah"]),
    ("chanukah", "chanukah", ["Chanukah"]),
    ("erevpurim", "purim", ["Purim"]),
    ("purim", "purim", ["Purim"]),
    ("erevpesach", "pesach", ["Pesach I", "Pesach II"]),
    ("pesach", "pesach", ["Pesach I", "Pesach II"]),
    ("erevshavuot", "shavuot", ["Shavuot"]),
    ("shavuot", "shavuot", ["Shavuot"]),
]
# Not festivals with a derush here, though their keys share a prefix above.
HOLIDAY_EXCLUDE = {"pesachsheni", "roshhashanalabehemot", "purimkatan", "shushanpurimkatan", "purimmeshulash"}

EXTRA_ALIASES = {
    "vezothaberakhah": "V'Zot HaBerachah",
    "vezothaberachah": "V'Zot HaBerachah",
    "vzothaberakhah": "V'Zot HaBerachah",
    "vzothaberachah": "V'Zot HaBerachah",
    "chayeisarah": "Chayei Sara",
    "metzorah": "Metzora",
    "behaalotecha": "Beha'alotcha",
    "behaaloscha": "Beha'alotcha",
    "shelach": "Sh'lach",
    "shelachlecha": "Sh'lach",
    "shlachlecha": "Sh'lach",
    "kitissa": "Ki Tisa",
    "kiteze": "Ki Teitzei",
    "ekev": "Eikev",
    "reeh": "Re'eh",
    "haazinu": "Ha'Azinu",
    "pekudey": "Pekudei",
    "vayakheil": "Vayakhel",
}

HEBREW_RE = re.compile(r"[\u0590-\u05FF]")
LATIN_RE = re.compile(r"[A-Za-z]")
TAG_RE = re.compile(r"</?([a-zA-Z][a-zA-Z0-9]*)\b[^>]*>")

# A paragraph that opens a derush on a verse: a quotation, usually ending in
# וגו' or כו', then the citation, e.g. "וישב יעקב בארץ מגורי אביו וגו' (לז א)".
# Inside its own book the edition omits the book's name.
TORAH_BOOK_NAMES = {"בראשית": 1, "שמות": 2, "ויקרא": 3, "במדבר": 4, "דברים": 5}
_NUM = r"[א-ת]{1,3}[\"׳'״]?"
CITATION_RE = re.compile(
    r"\(\s*(?:(?P<book>" + "|".join(TORAH_BOOK_NAMES) + r")\s+)?"
    r"(?P<chapter>" + _NUM + r")\s+(?P<verse>" + _NUM + r")"
    r"(?:\s*-\s*[^()]{1,14})?\s*\)"
)
# Words that stand for "and so on" inside a quotation, and openings that introduce one.
ELLIPSIS_WORDS = {"וגו", "כו", "וכו", "וגומר"}
QUOTE_LEADS = (("או", "יאמר"), ("עוד", "יאמר"))
LETTER_VALUES = dict(zip("אבגדהוזחטיכלמנסעפצקרשת", [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 200, 300, 400]))
LETTER_VALUES.update({"ך": 20, "ם": 40, "ן": 50, "ף": 80, "ץ": 90})

# Characters that write an abbreviation (חז"ל) or a numeral (ל"ב). The search
# index drops them, and so does the app's query, so חזל and חז"ל both match.
QUOTE_CHARS = "\"'׳״`’‘”“"
_QUOTE_RE = re.compile("[" + re.escape(QUOTE_CHARS) + "]")
# Hebrew points and cantillation. This edition has none, but a pasted query may.
_NIKUD_OR_CANTILLATION = re.compile(r"[\u0591-\u05bd\u05bf\u05c1\u05c2\u05c4\u05c5\u05c7]")


@dataclass
class Paragraph:
    section_id: int
    index: int
    body: str
    cite_book: int | None = None
    cite_chapter: int | None = None
    cite_verse: int | None = None

    @property
    def id(self) -> int:
        return stable_id(self.section_id, self.index)


@dataclass
class WeekRow:
    """One Shabbat: its parasha and any special Shabbat."""

    date: str
    israel: bool
    hdate: str = ""
    parashot: list[str] = field(default_factory=list)
    hebcal_parasha: str = ""
    specials: list[tuple[str, list[str]]] = field(default_factory=list)


@dataclass
class FestivalDay:
    """One day of a festival (or its eve) that Bas Ayin has derashot for.

    The app adds a festival to "this week" when one of its days falls between
    today and the coming Shabbat, so a festival does not linger for the rest of
    a week after it ends.
    """

    date: str
    israel: bool
    label: str
    keys: list[str]


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def stable_id(section_id: int, index: int) -> int:
    if not (1 <= section_id < 1000 and 1 <= index < 1000):
        fail(f"paragraph does not fit the stable id: {section_id=} {index=}")
    return section_id * 1000 + index


def gematria(letters: str) -> int:
    return sum(LETTER_VALUES.get(char, 0) for char in letters)


def plain_text(markup: str) -> str:
    text = re.sub(r"<[^>]+>", "", markup)
    text = _NIKUD_OR_CANTILLATION.sub("", text)
    return re.sub(r"\s+", " ", text).strip()


def search_text(markup: str) -> str:
    """What the FTS index holds: plain text without quotes, so abbreviations are one word."""
    return re.sub(r"\s+", " ", _QUOTE_RE.sub("", plain_text(markup))).strip()


def letters_key(title: str) -> str:
    text = title.strip()
    text = re.sub(r"^parashat\s+", "", text, flags=re.IGNORECASE)
    text = re.sub(r"^parshat\s+", "", text, flags=re.IGNORECASE)
    return re.sub(r"[^a-z]", "", text.lower())


def build_alias_map() -> dict[str, str]:
    mapping = {letters_key(key): key for key in PARASHA_KEYS}
    mapping.update(EXTRA_ALIASES)
    return mapping


ALIAS_MAP = build_alias_map()


def resolve_hebcal_parasha(title: str) -> list[str]:
    """Map a Hebcal English parasha title to one or two parasha keys."""
    cleaned = re.sub(r"^parashat\s+", "", title.strip(), flags=re.IGNORECASE)
    cleaned = re.sub(r"^parshat\s+", "", cleaned, flags=re.IGNORECASE)
    full = letters_key(cleaned)
    if full in ALIAS_MAP:
        return [ALIAS_MAP[full]]
    parts = re.split(r"\s*[-–—]\s*", cleaned)
    if len(parts) > 1:
        resolved = []
        for part in parts:
            key = letters_key(part)
            if key not in ALIAS_MAP:
                fail(f"unrecognised Hebcal parasha component {part!r} in {title!r}")
            resolved.append(ALIAS_MAP[key])
        return resolved
    fail(f"unrecognised Hebcal parasha title {title!r} (key {full!r})")


def holiday_sections(title: str, israel: bool) -> tuple[str, list[str]] | None:
    key = letters_key(title)
    if key in HOLIDAY_EXCLUDE:
        return None
    # In Israel, Shemini Atzeret and Simchat Torah are one day, and Hebcal calls it
    # Shmini Atzeret. That is the reading of V'Zot HaBerachah.
    if key in {"shminiatzeret", "sheminiatzeret"}:
        if israel:
            return ("simchat_torah", ["V'Zot HaBerachah"])
        # Bas Ayin has no derush of its own for Shemini Atzeret; it closes Sukkot.
        return ("shemini_atzeret", ["Sukkot"])
    for prefix, label, keys in HOLIDAY_PREFIXES:
        if key.startswith(prefix):
            return (label, keys)
    return None


def is_chol_hamoed_pesach(title: str) -> bool:
    key = letters_key(title)
    return key.startswith("pesach") and "chm" in key


def sections_for_parashot(parashot: list[str]) -> list[str]:
    """Bas Ayin sections for a week's parasha or parshiyot.

    A section counts when every parasha it covers is read that week. A parasha
    with no section of its own (Pekudei, Matot) takes the combined section.
    """
    week = set(parashot)
    chosen = [s.key for s in SECTION_DEFS if s.covers and set(s.covers) <= week]
    for parasha in parashot:
        if not any(parasha in SECTION_DEFS[SECTION_IDS[key] - 1].covers for key in chosen):
            chosen += [s.key for s in SECTION_DEFS if parasha in s.covers and s.key not in chosen]
    return sorted(chosen, key=lambda key: SECTION_IDS[key])


def self_test() -> None:
    assert plain_text("<b>וישב</b> יעקב") == "וישב יעקב"
    assert search_text('אמרו <b>חז"ל</b> וגו\'') == "אמרו חזל וגו"
    assert gematria("לז") == 37 and gematria("טו") == 15 and gematria("קמה") == 145
    samples = {
        "Parashat Bereshit": ["Bereshit"],
        "Parashat Lech-Lecha": ["Lech Lecha"],
        "Parashat Beha’alotcha": ["Beha'alotcha"],
        "Parashat Sh’lach": ["Sh'lach"],
        "Parashat Re’eh": ["Re'eh"],
        "Parashat Ha’azinu": ["Ha'Azinu"],
        "Parashat Vayakhel-Pekudei": ["Vayakhel", "Pekudei"],
        "Parashat Behar-Bechukotai": ["Behar", "Bechukotai"],
        "Parashat Matot-Masei": ["Matot", "Masei"],
        "Parashat Ki Teitzei": ["Ki Teitzei"],
        "Parashat Vezot Haberakhah": ["V'Zot HaBerachah"],
    }
    for title, expected in samples.items():
        got = resolve_hebcal_parasha(title)
        if got != expected:
            fail(f"title map {title!r} -> {got} expected {expected}")
    week_cases = {
        ("Vayakhel",): ["Vayakhel"],
        ("Pekudei",): ["Vayakhel Pekudei"],
        ("Vayakhel", "Pekudei"): ["Vayakhel", "Vayakhel Pekudei"],
        ("Matot",): ["Matot Masei"],
        ("Masei",): ["Masei"],
        ("Matot", "Masei"): ["Matot Masei", "Masei"],
        ("Behar", "Bechukotai"): ["Behar", "Behar Bechukotai", "Bechukotai"],
        ("Tazria", "Metzora"): ["Tazria", "Metzora"],
        ("Noach",): ["Noach"],
    }
    for parashot, expected in week_cases.items():
        got = sections_for_parashot(list(parashot))
        if got != expected:
            fail(f"week {parashot} -> {got} expected {expected}")
    assert holiday_sections("Chanukah: 3 Candles", False) == ("chanukah", ["Chanukah"])
    assert holiday_sections("Pesach Sheni", False) is None
    assert holiday_sections("Shmini Atzeret", True) == ("simchat_torah", ["V'Zot HaBerachah"])
    assert holiday_sections("Shmini Atzeret", False) == ("shemini_atzeret", ["Sukkot"])
    assert holiday_sections("Rosh Hashana 5787", False)[0] == "rosh_hashanah"
    assert is_chol_hamoed_pesach("Pesach IV (CH’’M)") and not is_chol_hamoed_pesach("Pesach VII")
    torah = {1: [[""] * 40 for _ in range(50)]}
    torah[1][36][0] = "וַיֵּשֶׁב יַעֲקֹב בְּאֶרֶץ מְגוּרֵי אָבִיו בְּאֶרֶץ כְּנָעַן"
    torah[1][5][4] = "וַיַּרְא יְהוָה כִּי רַבָּה רָעַת הָאָדָם בָּאָרֶץ"
    assert detect_citation('<b>וישב</b> יעקב בארץ מגורי אביו וגו\' (לז א). הנה', 1, torah) == (1, 37, 1)
    assert detect_citation("<b>וישב</b> יעקב (לז א). פירש", 1, torah) == (1, 37, 1)
    assert detect_citation("<b>ולהבין</b> זה, הנה כתוב (בראשית ו ה) כי", 1, torah) is None
    assert detect_citation("<b>וזהו</b> (בראשית לז א) וישב יעקב", 1, torah) is None
    assert detect_citation("<b>וזה</b> וישב יעקב וגו' (לז א)", 1, torah) is None
    torah[1][0][0] = "בְּרֵאשִׁית בָּרָא אֱלֹהִים אֵת הַשָּׁמַיִם וְאֵת הָאָרֶץ"
    torah[1][0][1] = "וְהָאָרֶץ הָיְתָה תֹהוּ וָבֹהוּ"
    assert detect_citation("<b>בראשית ברא וגו' והארץ היתה תהו ובהו וגו'</b> (בראשית א א - ג). לפרש", 1, torah) == (1, 1, 1)


def fetch(url: str, retries: int = 4) -> bytes:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256(url.encode("utf-8")).hexdigest()[:24]
    cache_path = CACHE_DIR / digest
    meta_path = CACHE_DIR / f"{digest}.url"
    if cache_path.exists() and meta_path.exists() and meta_path.read_text(encoding="utf-8") == url:
        return cache_path.read_bytes()
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    delay = 1.5
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                body = response.read()
            cache_path.write_bytes(body)
            meta_path.write_text(url, encoding="utf-8")
            time.sleep(0.15)
            return body
        except urllib.error.HTTPError as error:
            last_error = error
            if error.code not in {429, 500, 502, 503, 504} or attempt == retries:
                detail = error.read()[:300]
                fail(f"HTTP {error.code} for {url}: {detail!r}")
        except urllib.error.URLError as error:
            last_error = error
            if attempt == retries:
                fail(f"network error for {url}: {error}")
        time.sleep(delay)
        delay *= 2
    fail(f"failed to fetch {url}: {last_error}")


def fetch_json(url: str) -> object:
    try:
        return json.loads(fetch(url).decode("utf-8"))
    except json.JSONDecodeError as error:
        fail(f"invalid JSON from {url}: {error}")


def version_url(title: str, version_title: str) -> str:
    filename = quote(f"{title} - he - {version_title}.json", safe="")
    return f"https://www.sefaria.org/download/version/{filename}?raw=1"


def index_url(title: str) -> str:
    # The resolved index: nodes named by a shared term (the parshiyot) carry heTitle here.
    return f"https://www.sefaria.org/api/v2/index/{title.replace(' ', '_')}"


def hebcal_url(year: int, israel: bool) -> str:
    flag = "on" if israel else "off"
    return (
        "https://www.hebcal.com/hebcal?v=1&cfg=json"
        f"&year={year}&month=x&s=on&maj=on&min=on&mod=off&nx=off"
        f"&mf=off&ss=on&c=off&geo=none&M=off&leyning=off&i={flag}"
    )


def require_version(doc: dict, url: str) -> None:
    if doc.get("versionTitle") != TEXT_VERSION:
        fail(f"{url} versionTitle is {doc.get('versionTitle')!r}, expected exactly {TEXT_VERSION!r}")
    if doc.get("license") != TEXT_LICENSE:
        fail(f"{url} licence is {doc.get('license')!r}, expected {TEXT_LICENSE!r}")
    if doc.get("language") != "he":
        fail(f"{url} language is {doc.get('language')!r}, expected Hebrew")


def check_index(index: dict) -> None:
    nodes = index.get("schema", {}).get("nodes")
    if not isinstance(nodes, list):
        fail("Bat Ayin index has no schema nodes")
    keys = [node.get("key") for node in nodes]
    expected = [section.key for section in SECTION_DEFS]
    if keys != expected:
        fail(f"Bat Ayin sections changed upstream:\n got {keys}\n expected {expected}")
    for node, section in zip(nodes, SECTION_DEFS):
        hebrew = node.get("heTitle") or next(
            (title["text"] for title in node.get("titles", []) if title.get("lang") == "he" and title.get("primary")),
            None,
        )
        if hebrew != section.he:
            fail(f"Hebrew title of {section.key} is {hebrew!r}, expected {section.he!r}")


def normalize_markup(raw: str) -> str:
    """Keep <b>, which the edition uses for the opening word of a paragraph and for
    verse quotations. Drop every other tag and keep its words."""
    text = unescape(raw).replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.IGNORECASE)
    text = TAG_RE.sub(lambda match: match.group(0) if match.group(1).lower() == "b" else "", text)
    text = re.sub(r"<b>\s*</b>", "", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r" *\n *", "\n", text).strip()
    if text.count("<b>") != text.count("</b>"):
        fail(f"unbalanced <b> in {text[:120]!r}")
    return text


def hebrew_words(text: str) -> list[str]:
    """Letters-only words: no tags, points, quote marks, maqaf or punctuation."""
    text = _NIKUD_OR_CANTILLATION.sub("", re.sub(r"<[^>]+>", " ", text))
    text = _QUOTE_RE.sub("", text.replace("\u05be", " "))
    return re.findall(r"[\u05d0-\u05ea]+", text)


def skeleton(word: str) -> str:
    """A word without ו and י after its first letter, so full and defective spellings compare equal."""
    return word[:1] + re.sub("[וי]", "", word[1:])


def quote_opens_verse(before: str, verses: list[str]) -> bool:
    """The paragraph's opening words are the first words of its quotation of the cited verse(s)."""
    words = hebrew_words(before)
    for lead in QUOTE_LEADS:
        if tuple(words[: len(lead)]) == lead:
            words = words[len(lead):]
    # Only the words before the first "and so on": the quotation skips there, so the
    # next words are from further on, as in "בראשית ברא וגו' והארץ היתה תהו".
    cut = next((i for i, word in enumerate(words) if word in ELLIPSIS_WORDS), len(words))
    probe = [skeleton(word) for word in words[:cut][:3]]
    if len(probe) < 2 and not (probe and len(probe[0]) >= 3):
        return False
    target = [skeleton(word) for word in hebrew_words(" ".join(verses))]
    return any(target[i : i + len(probe)] == probe for i in range(len(target) - len(probe) + 1))


def detect_citation(
    markup: str, book_id: int | None, torah: dict[int, list[list[str]]]
) -> tuple[int, int, int] | None:
    """(book, chapter, verse) when the paragraph opens by quoting a verse and citing it,
    as a derush on that verse does: "וישב יעקב בארץ מגורי אביו וגו' (לז א)". Otherwise None."""
    text = plain_text(markup)
    match = CITATION_RE.search(text)
    if not match or match.start() >= 300:
        return None
    before = text[: match.start()].strip()
    if not before or "(" in before:
        return None
    book = TORAH_BOOK_NAMES.get(match.group("book") or "", book_id)
    if book is None or book not in torah:
        return None
    chapter = gematria(match.group("chapter"))
    verse = gematria(match.group("verse"))
    chapters = torah[book]
    if not (1 <= chapter <= len(chapters) and 1 <= verse <= len(chapters[chapter - 1])):
        return None
    # A quotation can run into the next verses, as in (א א - ג).
    if not quote_opens_verse(before, chapters[chapter - 1][verse - 1 : verse + 3]):
        return None
    return (book, chapter, verse)


def load_paragraphs(doc: dict, torah: dict[int, list[list[str]]]) -> list[Paragraph]:
    text = doc.get("text")
    if not isinstance(text, dict):
        fail("Bat Ayin version text is not an object of sections")
    paragraphs: list[Paragraph] = []
    for section_id, section in enumerate(SECTION_DEFS, start=1):
        node = text.get(section.key)
        if not isinstance(node, list) or not node:
            fail(f"section {section.key} is missing or empty")
        index = 0
        for raw in node:
            if raw is None or raw == "":
                continue
            if not isinstance(raw, str):
                fail(f"{section.key} has a {type(raw).__name__} paragraph")
            markup = normalize_markup(raw)
            if not markup:
                continue
            index += 1
            paragraph = Paragraph(section_id, index, markup)
            if section.kind != "appendix":
                cite = detect_citation(markup, section.book, torah)
                if cite:
                    paragraph.cite_book, paragraph.cite_chapter, paragraph.cite_verse = cite
            paragraphs.append(paragraph)
    return paragraphs


def assert_hebrew_corpus(samples: list[str]) -> None:
    hebrew = 0
    latin = 0
    offenders: list[str] = []
    for text in samples:
        plain = re.sub(r"<[^>]+>", "", text)
        h = len(HEBREW_RE.findall(plain))
        lat = len(LATIN_RE.findall(plain))
        hebrew += h
        latin += lat
        if lat > 40 and lat > h:
            offenders.append(plain[:180])
    if offenders:
        fail("refusing Latin-heavy paragraphs (possible translation):\n" + "\n".join(offenders[:5]))
    if hebrew < 100_000 or latin * 50 > hebrew:
        fail(f"Hebrew corpus check failed (hebrew letters={hebrew}, latin letters={latin})")


def collect_calendar(years: range) -> tuple[list[WeekRow], list[FestivalDay]]:
    """One row per Shabbat, and one per festival day, for each calendar."""
    weeks: list[WeekRow] = []
    festivals: list[FestivalDay] = []
    for israel in (True, False):
        items_by_date: dict[str, list[dict]] = {}
        for year in years:
            url = hebcal_url(year, israel)
            print(f"  hebcal {year} {'israel' if israel else 'diaspora'}")
            payload = fetch_json(url)
            items = payload.get("items") if isinstance(payload, dict) else None
            if not isinstance(items, list):
                fail(f"Hebcal response has no items: {url}")
            for item in items:
                if not isinstance(item, dict):
                    continue
                day = str(item.get("date") or "")[:10]
                if re.fullmatch(r"\d{4}-\d{2}-\d{2}", day):
                    bucket = items_by_date.setdefault(day, [])
                    if item not in bucket:
                        bucket.append(item)
        first = date(years.start, 1, 1)
        last = date(years.stop - 1, 12, 31)
        for day_iso in sorted(items_by_date):
            if not (first.isoformat() <= day_iso <= last.isoformat()):
                continue
            is_shabbat = date.fromisoformat(day_iso).weekday() == 5
            for item in items_by_date[day_iso]:
                title = str(item.get("title") or "")
                if item.get("category") != "holiday" or item.get("subcat") == "shabbat":
                    continue
                found = holiday_sections(title, israel)
                if not found:
                    continue
                label, keys = found
                if is_shabbat and is_chol_hamoed_pesach(title):
                    keys = keys + ["Shabbat Chol HaMoed Pesach"]
                festivals.append(FestivalDay(day_iso, israel, label, keys))
        day = first + timedelta(days=(5 - first.weekday()) % 7)  # the first Saturday
        while day <= last:
            row = WeekRow(date=day.isoformat(), israel=israel)
            for item in items_by_date.get(row.date, []):
                if item.get("hdate"):
                    row.hdate = item["hdate"]
                title = str(item.get("title") or "")
                if item.get("category") == "parashat":
                    row.hebcal_parasha = title
                    row.parashot = resolve_hebcal_parasha(title)
                elif item.get("category") == "holiday" and item.get("subcat") == "shabbat":
                    special = SPECIAL_SHABBAT.get(letters_key(title))
                    if special:
                        row.specials.append(special)
            weeks.append(row)
            day += timedelta(days=7)
    return weeks, festivals


def ordered_ids(keys: list[str]) -> list[int]:
    ids: list[int] = []
    for key in keys:
        if SECTION_IDS[key] not in ids:
            ids.append(SECTION_IDS[key])
    return ids


def week_sections(row: WeekRow) -> list[int]:
    keys: list[str] = sections_for_parashot(row.parashot) if row.parashot else []
    for _label, special_keys in row.specials:
        keys += special_keys
    return ordered_ids(keys)


def week_title(row: WeekRow) -> tuple[str, str]:
    he_parts: list[str] = []
    en_parts: list[str] = []
    if row.parashot:
        he_parts.append("־".join(PARASHA_NAMES[key][0] for key in row.parashot))
        en_parts.append("-".join(PARASHA_NAMES[key][1] for key in row.parashot))
    for label, _keys in row.specials:
        if LABELS[label][0] not in he_parts:
            he_parts.append(LABELS[label][0])
            en_parts.append(LABELS[label][1])
    return " · ".join(he_parts), " · ".join(en_parts)


def reading_for(connection: sqlite3.Connection, today: date, israel: bool) -> tuple[str, list[int]]:
    """The app's "this week", for checks here. CommentaryStore.currentReading does the same:
    the coming Shabbat (today, if it is Shabbat), and each festival with a day between today
    and that Shabbat. Festivals follow in date order; within one, sections keep the edition order."""
    shabbat = today + timedelta(days=(5 - today.weekday()) % 7)
    row = connection.execute(
        "SELECT title_he, section_ids FROM weekly WHERE gregorian_date = ? AND israel = ?",
        (shabbat.isoformat(), 1 if israel else 0),
    ).fetchone()
    if row is None:
        return "", []
    parts = [part for part in str(row[0]).split(" · ") if part]
    ids = [int(value) for value in str(row[1]).split(",") if value]
    groups: dict[str, set[int]] = {}
    for label_he, section_ids in connection.execute(
        """
        SELECT title_he, section_ids FROM festival_days
        WHERE israel = ? AND gregorian_date BETWEEN ? AND ?
        ORDER BY gregorian_date
        """,
        (1 if israel else 0, today.isoformat(), shabbat.isoformat()),
    ):
        groups.setdefault(label_he, set()).update(int(value) for value in section_ids.split(","))
    for label_he, group in groups.items():
        if label_he not in parts:
            parts.append(label_he)
        ids += [value for value in sorted(group) if value not in ids]
    return " · ".join(parts), ids


def create_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        PRAGMA foreign_keys = ON;

        CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE books (
            id INTEGER PRIMARY KEY,
            en_key TEXT NOT NULL,
            he_name TEXT NOT NULL,
            en_name TEXT NOT NULL,
            sort_order INTEGER NOT NULL
        );

        CREATE TABLE sections (
            id INTEGER PRIMARY KEY,
            book_id INTEGER REFERENCES books(id),
            sefaria_key TEXT NOT NULL,
            he_name TEXT NOT NULL,
            en_name TEXT NOT NULL,
            kind TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            moed_order INTEGER,
            parashot TEXT NOT NULL,
            redirect_id INTEGER REFERENCES sections(id)
        );

        CREATE TABLE paragraphs (
            id INTEGER PRIMARY KEY,
            section_id INTEGER NOT NULL REFERENCES sections(id),
            paragraph_index INTEGER NOT NULL,
            body TEXT NOT NULL,
            cite_book_id INTEGER REFERENCES books(id),
            cite_chapter INTEGER,
            cite_verse INTEGER
        );

        CREATE TABLE weekly (
            gregorian_date TEXT NOT NULL,
            israel INTEGER NOT NULL,
            hebcal_parasha TEXT NOT NULL,
            hdate TEXT NOT NULL,
            title_he TEXT NOT NULL,
            title_en TEXT NOT NULL,
            section_ids TEXT NOT NULL,
            PRIMARY KEY (gregorian_date, israel)
        );

        CREATE TABLE festival_days (
            gregorian_date TEXT NOT NULL,
            israel INTEGER NOT NULL,
            label TEXT NOT NULL,
            title_he TEXT NOT NULL,
            title_en TEXT NOT NULL,
            section_ids TEXT NOT NULL,
            PRIMARY KEY (gregorian_date, israel, label)
        );

        CREATE INDEX idx_paragraphs_section ON paragraphs(section_id, paragraph_index);
        CREATE INDEX idx_weekly_lookup ON weekly(israel, gregorian_date);
        CREATE INDEX idx_festival_lookup ON festival_days(israel, gregorian_date);
        """
    )


def add_search_index(connection: sqlite3.Connection) -> None:
    """FTS5 over the paragraphs without tags or quote marks, so חזל and חז"ל both match."""
    connection.execute("DROP TABLE IF EXISTS paragraphs_fts")
    connection.execute(
        """
        CREATE VIRTUAL TABLE paragraphs_fts USING fts5(
            paragraph_id UNINDEXED,
            plain,
            tokenize = 'unicode61 remove_diacritics 2'
        )
        """
    )
    rows = [(pid, search_text(body)) for pid, body in connection.execute("SELECT id, body FROM paragraphs")]
    connection.executemany("INSERT INTO paragraphs_fts (paragraph_id, plain) VALUES (?, ?)", rows)


def write_database(
    output: Path,
    paragraphs: list[Paragraph],
    weekly: list[WeekRow],
    festivals: list[FestivalDay],
    meta: dict[str, str],
) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    connection = sqlite3.connect(output)
    try:
        create_schema(connection)
        connection.executemany(
            "INSERT INTO books (id, en_key, he_name, en_name, sort_order) VALUES (?, ?, ?, ?, ?)",
            [(book_id, key, he, en, book_id) for book_id, key, he, en in BOOKS],
        )
        connection.executemany(
            """
            INSERT INTO sections (
                id, book_id, sefaria_key, he_name, en_name, kind, sort_order, moed_order, parashot, redirect_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    section_id,
                    section.book,
                    section.key,
                    section.he,
                    section.en,
                    section.kind,
                    section_id,
                    section.moed_order,
                    ",".join(section.covers),
                    None,
                )
                for section_id, section in enumerate(SECTION_DEFS, start=1)
            ],
        )
        # A pointer can name a later section, so set it once every section exists.
        connection.executemany(
            "UPDATE sections SET redirect_id = ? WHERE id = ?",
            [
                (SECTION_IDS[section.redirect], section_id)
                for section_id, section in enumerate(SECTION_DEFS, start=1)
                if section.redirect
            ],
        )
        connection.executemany(
            """
            INSERT INTO paragraphs (id, section_id, paragraph_index, body, cite_book_id, cite_chapter, cite_verse)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (p.id, p.section_id, p.index, p.body, p.cite_book, p.cite_chapter, p.cite_verse)
                for p in paragraphs
            ],
        )
        weekly_rows = []
        for row in weekly:
            title_he, title_en = week_title(row)
            weekly_rows.append(
                (
                    row.date,
                    1 if row.israel else 0,
                    row.hebcal_parasha,
                    row.hdate,
                    title_he,
                    title_en,
                    ",".join(str(value) for value in week_sections(row)),
                )
            )
        connection.executemany(
            """
            INSERT INTO weekly (gregorian_date, israel, hebcal_parasha, hdate, title_he, title_en, section_ids)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            weekly_rows,
        )
        merged: dict[tuple[str, bool, str], list[str]] = {}
        for day in festivals:
            keys = merged.setdefault((day.date, day.israel, day.label), [])
            keys += [key for key in day.keys if key not in keys]
        connection.executemany(
            """
            INSERT INTO festival_days (gregorian_date, israel, label, title_he, title_en, section_ids)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    day_iso,
                    1 if israel else 0,
                    label,
                    LABELS[label][0],
                    LABELS[label][1],
                    ",".join(str(value) for value in sorted(SECTION_IDS[key] for key in keys)),
                )
                for (day_iso, israel, label), keys in sorted(merged.items())
            ],
        )
        connection.executemany("INSERT INTO meta (key, value) VALUES (?, ?)", list(meta.items()))
        add_search_index(connection)
        connection.commit()
        connection.execute("VACUUM")
    finally:
        connection.close()


def validate_database(path: Path, year_start: int, year_end: int) -> dict:
    if not path.exists():
        fail(f"database not found: {path}")
    connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row

    def one(sql: str, *args: object) -> object:
        return connection.execute(sql, args).fetchone()[0]

    try:
        meta = {row["key"]: row["value"] for row in connection.execute("SELECT key, value FROM meta")}
        if meta.get("text_version") != TEXT_VERSION:
            fail(f"bundled text version is {meta.get('text_version')!r}, expected {TEXT_VERSION!r}")
        if meta.get("text_license") != TEXT_LICENSE:
            fail(f"bundled text licence is {meta.get('text_license')!r}, expected {TEXT_LICENSE!r}")
        if meta.get("translation_included") != "no":
            fail("the database must not include a translation")
        books = one("SELECT COUNT(*) FROM books")
        sections = one("SELECT COUNT(*) FROM sections")
        if books != 5 or sections != len(SECTION_DEFS):
            fail(f"expected 5 books and {len(SECTION_DEFS)} sections, found {books} and {sections}")
        keys = [row[0] for row in connection.execute("SELECT sefaria_key FROM sections ORDER BY sort_order")]
        if keys != [section.key for section in SECTION_DEFS]:
            fail("section order differs from SECTION_DEFS")
        empty = [
            row[0]
            for row in connection.execute(
                """
                SELECT s.sefaria_key FROM sections s
                LEFT JOIN paragraphs p ON p.section_id = s.id
                GROUP BY s.id HAVING COUNT(p.id) = 0
                """
            )
        ]
        if empty:
            fail(f"sections without paragraphs: {empty}")
        paragraphs = one("SELECT COUNT(*) FROM paragraphs")
        if paragraphs < 2500:
            fail(f"too few paragraphs: {paragraphs}")
        redirects = {
            row[0]: row[1]
            for row in connection.execute(
                """
                SELECT s.sefaria_key, t.sefaria_key FROM sections s
                JOIN sections t ON t.id = s.redirect_id
                """
            )
        }
        if redirects != {"Parashat Shekalim": "Ki Tisa", "Parashat Parah": "Chukat"}:
            fail(f"unexpected pointer sections: {redirects}")
        moadim = one("SELECT COUNT(*) FROM sections WHERE moed_order IS NOT NULL")
        distinct_orders = one("SELECT COUNT(DISTINCT moed_order) FROM sections WHERE moed_order IS NOT NULL")
        if moadim != 17 or distinct_orders != 17:
            fail(f"expected 17 festival sections with distinct order, found {moadim} / {distinct_orders}")
        bodies = [row[0] for row in connection.execute("SELECT body FROM paragraphs")]
        assert_hebrew_corpus(bodies)
        if any(TAG_RE.search(body.replace("<b>", "").replace("</b>", "")) for body in bodies):
            fail("paragraphs contain tags other than <b>")
        opening = one("SELECT body FROM paragraphs WHERE id = ?", stable_id(1, 1))
        if not opening or "בראשית ברא" not in plain_text(str(opening)):
            fail("Bereshit does not open with בראשית ברא")
        citations = one("SELECT COUNT(*) FROM paragraphs WHERE cite_verse IS NOT NULL")
        if citations < 100:
            fail(f"too few verse citations detected: {citations}")
        vayeshev = one("SELECT cite_chapter || ':' || cite_verse FROM paragraphs WHERE id = ?", stable_id(SECTION_IDS["Vayeshev"], 1))
        if vayeshev != "37:1":
            fail(f"Vayeshev 1 should cite Genesis 37:1, found {vayeshev}")
        max_index = one("SELECT MAX(paragraph_index) FROM paragraphs")
        if max_index >= 1000:
            fail("paragraph index overflowed the stable id width")

        weekly = one("SELECT COUNT(*) FROM weekly")
        if weekly < 52 * (year_end - year_start + 1) * 2:
            fail(f"weekly table is too small: {weekly}")
        bare = one(
            """
            SELECT COUNT(*) FROM weekly w
            WHERE w.section_ids = ''
              AND NOT EXISTS (
                SELECT 1 FROM festival_days f
                WHERE f.gregorian_date = w.gregorian_date AND f.israel = w.israel
              )
            """
        )
        if bare:
            fail(f"{bare} Shabbatot have neither a section nor a festival")
        known_ids = set(range(1, len(SECTION_DEFS) + 1))
        used: set[int] = set()
        for table in ("weekly", "festival_days"):
            for row in connection.execute(f"SELECT section_ids FROM {table} WHERE section_ids != ''"):
                for part in row[0].split(","):
                    if int(part) not in known_ids:
                        fail(f"{table} references unknown section id {part}")
                    used.add(int(part))
        unused = [SECTION_DEFS[i - 1].key for i in sorted(known_ids - used) if SECTION_DEFS[i - 1].kind != "appendix"]
        if unused:
            fail(f"sections never reached from the calendar: {unused}")
        for israel in (0, 1):
            span = connection.execute(
                "SELECT MIN(gregorian_date), MAX(gregorian_date) FROM weekly WHERE israel = ?", (israel,)
            ).fetchone()
            if span[0][:4] > str(year_start) or span[1][:4] < str(year_end):
                fail(f"weekly calendar israel={israel} does not cover {year_start}-{year_end}: {span[0]}..{span[1]}")
        for label in ("rosh_hashanah", "yom_kippur", "sukkot", "shemini_atzeret", "simchat_torah", "chanukah", "purim", "pesach", "shavuot"):
            years = one(
                "SELECT COUNT(DISTINCT substr(gregorian_date, 1, 4)) FROM festival_days WHERE label = ? AND israel = 0",
                label,
            )
            if years < (year_end - year_start):
                fail(f"{label} is missing from too many years ({years})")
        # The same rule as the app, on dates whose answer is known.
        checks = [
            (date(2026, 11, 21), False, ["Vayetzei"], ["Chanukah"]),
            (date(2026, 9, 13), False, ["Ha'Azinu", "Shabbat Shuvah I", "Rosh HaShanah"], []),
            (date(2026, 9, 14), False, ["Ha'Azinu", "Shabbat Shuvah II"], ["Rosh HaShanah", "Erev Rosh HaShanah"]),
            (date(2026, 12, 6), True, ["Miketz", "Chanukah"], ["Vayeshev"]),
            (date(2026, 4, 4), False, ["Pesach I", "Shabbat Chol HaMoed Pesach", "Pesach II"], []),
            (date(2026, 10, 4), False, ["Bereshit", "V'Zot HaBerachah"], []),
            (date(2026, 10, 4), True, ["Bereshit"], ["V'Zot HaBerachah"]),
            (date(2026, 3, 9), False, ["Vayakhel", "Vayakhel Pekudei", "Parashat HaChodesh"], ["Purim"]),
        ]
        for day, israel, present, absent in checks:
            title, ids = reading_for(connection, day, israel)
            keys = [SECTION_DEFS[i - 1].key for i in ids]
            if not title or any(key not in keys for key in present) or any(key in keys for key in absent):
                fail(f"this week on {day} israel={israel}: {title!r} {keys}")
        combined = one("SELECT COUNT(*) FROM weekly WHERE hebcal_parasha LIKE '%-%'")
        if combined < 20:
            fail("combined parshiyot are missing from the weekly table")
        differ = one(
            """
            SELECT COUNT(*) FROM weekly a
            JOIN weekly b ON a.gregorian_date = b.gregorian_date AND a.israel = 1 AND b.israel = 0
            WHERE a.section_ids != b.section_ids
            """
        )
        if differ < 1:
            fail("Israel and Diaspora schedules are identical; the setting would do nothing")

        if one("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'paragraphs_fts'") != 1:
            fail("paragraphs_fts is missing")
        for query in ('"חנוכה"*', '"חזל"*'):
            if not connection.execute("SELECT 1 FROM paragraphs_fts WHERE paragraphs_fts MATCH ? LIMIT 1", (query,)).fetchone():
                fail(f"search for {query} found nothing")
        if connection.execute("SELECT 1 FROM paragraphs_fts WHERE plain LIKE '%\"%' LIMIT 1").fetchone():
            fail("search index still contains quote marks")
        return {
            "books": books,
            "sections": sections,
            "festival_sections": moadim,
            "paragraphs": paragraphs,
            "verse_citations": citations,
            "max_paragraph_index": max_index,
            "weekly_rows": weekly,
            "festival_days": one("SELECT COUNT(*) FROM festival_days"),
            "combined_weeks": combined,
            "israel_diaspora_differences": differ,
            "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "search": "fts5, tags and quote marks removed",
        }
    finally:
        connection.close()


def build(output: Path, manifest_path: Path, year_start: int, year_end: int) -> None:
    if year_end < year_start:
        fail("year range is empty")
    print("downloading the Sefaria index")
    index = fetch_json(index_url(SEFARIA_TITLE))
    if not isinstance(index, dict):
        fail("Bat Ayin index is not an object")
    check_index(index)

    print(f"downloading the Torah ({TORAH_CHECK_VERSION}, {TORAH_CHECK_LICENSE}) to check verse citations")
    torah: dict[int, list[list[str]]] = {}
    for book_id, key, _he, _en in BOOKS:
        url = version_url(key, TORAH_CHECK_VERSION)
        payload = fetch_json(url)
        if not isinstance(payload, dict) or payload.get("versionTitle") != TORAH_CHECK_VERSION:
            fail(f"{url} is not {TORAH_CHECK_VERSION!r}")
        if payload.get("license") != TORAH_CHECK_LICENSE:
            fail(f"{url} licence is {payload.get('license')!r}")
        chapters = payload.get("text")
        if not isinstance(chapters, list) or not all(isinstance(chapter, list) for chapter in chapters):
            fail(f"{url} has no chapters")
        torah[book_id] = [[str(verse or "") for verse in chapter] for chapter in chapters]

    print(f"downloading Bat Ayin, {TEXT_VERSION} ({TEXT_LICENSE})")
    url = version_url(SEFARIA_TITLE, TEXT_VERSION)
    doc = fetch_json(url)
    if not isinstance(doc, dict):
        fail(f"{url} is not an object")
    require_version(doc, url)
    paragraphs = load_paragraphs(doc, torah)
    assert_hebrew_corpus([p.body for p in paragraphs])

    print(f"downloading Hebcal {year_start}-{year_end}")
    weekly, festivals = collect_calendar(range(year_start, year_end + 1))

    generated = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    meta = {
        "text_title": SEFARIA_TITLE,
        "text_version": TEXT_VERSION,
        "text_license": TEXT_LICENSE,
        "text_license_url": TEXT_LICENSE_URL,
        "text_source": TEXT_SOURCE,
        "text_version_source": str(doc.get("versionSource") or ""),
        "hebcal_license": "CC BY 4.0",
        "hebcal_attribution": "Torah reading and holiday schedule from Hebcal.com, CC BY 4.0",
        "hebcal_url": "https://www.hebcal.com/home/195/jewish-calendar-rest-api",
        "year_start": str(year_start),
        "year_end": str(year_end),
        "generated_utc": generated,
        "language": "he",
        "translation_included": "no",
    }
    write_database(output, paragraphs, weekly, festivals, meta)
    stats = validate_database(output, year_start, year_end)
    manifest = {
        "generated_utc": generated,
        "database": str(output.relative_to(ROOT)),
        "sha256": stats["sha256"],
        "bytes": stats["bytes"],
        "licenses": {
            "text": {
                "work": "Bat Ayin (בת עין), Rabbi Avraham Dov of Ovruch",
                "version": TEXT_VERSION,
                "version_source": meta["text_version_source"],
                "language": "he",
                "license": TEXT_LICENSE,
                "license_url": TEXT_LICENSE_URL,
                "publisher": "Sefaria",
                "note": "Non-commercial use only, with attribution. The app must stay free, without ads or in-app purchases.",
            },
            "calendar": {
                "provider": "Hebcal.com",
                "license": "CC BY 4.0",
                "url": "https://www.hebcal.com",
                "years": [year_start, year_end],
            },
        },
        "stats": stats,
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(stats, ensure_ascii=False, indent=2))
    print(f"wrote {output}")
    print(f"wrote {manifest_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the offline Bas Ayin SQLite database")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--year-start", type=int, default=DEFAULT_YEAR_START)
    parser.add_argument("--year-end", type=int, default=DEFAULT_YEAR_END)
    parser.add_argument("--validate-only", action="store_true", help="Check an existing database without downloading")
    parser.add_argument(
        "--index-only",
        action="store_true",
        help="Rebuild the FTS5 search index on an existing database without downloading",
    )
    args = parser.parse_args()
    self_test()
    if args.index_only:
        connection = sqlite3.connect(args.output)
        try:
            add_search_index(connection)
            connection.commit()
            connection.execute("VACUUM")
        finally:
            connection.close()
        print(f"rebuilt search index in {args.output}")
    if args.validate_only or args.index_only:
        stats = validate_database(args.output, args.year_start, args.year_end)
        print(json.dumps(stats, ensure_ascii=False, indent=2))
        return
    build(args.output, args.manifest, args.year_start, args.year_end)


if __name__ == "__main__":
    main()
