# בת עין

An offline iPhone and iPad app for reading **Bas Ayin** (בת עין, Bat Ayin), the derashot of Rabbi Avraham Dov of Ovruch (Avritch) on the Torah and the festivals, arranged by the weekly parasha and the Jewish year. It is built the same way as the [Ohr HaChaim app](https://github.com/dberrebi/OhrHachaim).

The book itself is Hebrew only. English is available for the interface: menus, settings, and help. There is no translation of the text.

The app does not use the network at runtime, and it has no analytics.

## Licence of the text: keep the app free

Sefaria has one Hebrew version of Bat Ayin, titled `Jerusalem, 2001`, and it is licensed **CC BY-NC 4.0** (Attribution-NonCommercial). Unlike the Ohr HaChaim text (CC0), this means:

- The app must stay free, with no ads, no in-app purchases, and no paid tip jar.
- The edition must be credited. The app does this in About, under every reading, and in every shared or copied paragraph.

For the same reason the support page in `docs/` has no donation link. Add one only if you are satisfied that it does not make the use of the text commercial.

## Open and run

Requirements: Xcode 15 or later to build locally, and a deployment target of iOS 17. Open `BasAyin/BasAyin.xcodeproj`. Apple has required Xcode 26 for App Store uploads since 28 April 2026. GitHub Actions uses the `macos-26` runner and selects Xcode 26, which includes the iOS 26 SDK, while the deployment target stays iOS 17.

No Apple Developer account is configured. Signing is turned off in the target so the project can compile without a team:

```bash
xcodebuild \
  -project BasAyin/BasAyin.xcodeproj \
  -scheme BasAyin \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

In Xcode, choose an iPhone or iPad simulator and run. Signing stays off for that, so no Apple ID is required.

## Install on your own iPhone for free

This uses a free Apple ID, not the paid Apple Developer Program. Apple's Personal Team allows up to 3 apps on a device and up to 3 devices; the provisioning profile expires after 7 days, after which the app will not open until you install it from Xcode again. Source: [About your developer account](https://developer.apple.com/help/account/basics/about-your-developer-account/).

1. Install Xcode from the Mac App Store.
2. In Xcode, open Settings → Accounts and sign in with your Apple ID. The team is shown as a Personal Team.
3. Open `BasAyin/BasAyin.xcodeproj`. Select the BasAyin app target, then Signing & Capabilities. Turn on Automatically manage signing and choose your Personal Team. If the bundle identifier is already registered to someone else, change it to a unique one, such as `app.basayin.yourname`.
4. The project file leaves code signing off so CI can build without a team. For this device install, set Code Signing Allowed to Yes on that target if Xcode still refuses to sign.
5. Connect the iPhone. On the phone, turn on Developer Mode under Settings → Privacy & Security when iOS asks, and restart if prompted.
6. Choose your iPhone as the run destination and press Run. If iOS says the developer is not trusted, open Settings → General → VPN & Device Management and trust your Apple ID.

## Install with TestFlight

This path uses the paid Apple Developer Program. `.github/workflows/testflight.yml` runs when the iOS workflow passes on a push to `main` (the data check, the build, and every unit and UI test), and uploads the commit that was tested. A manual run from the Actions tab (workflow_dispatch) uploads the commit it is started on without waiting for tests. Until the four secrets exist, the workflow prints which names are missing and finishes green.

Add the secrets under the repository's Settings → Secrets and variables → Actions → Repository secrets. Do not commit them.

| Secret | What to paste |
| --- | --- |
| `APPLE_TEAM_ID` | The 10-character Team ID from the Apple Developer membership page. |
| `ASC_KEY_ID` | The Key ID of an App Store Connect API key. |
| `ASC_ISSUER_ID` | The Issuer ID shown above the keys on that same page. |
| `ASC_KEY_P8` | The raw text of the downloaded `.p8` file, including the `BEGIN PRIVATE KEY` and `END PRIVATE KEY` lines. |

Create the API key in App Store Connect → Users and Access → Integrations → App Store Connect API, with a role that can upload builds (Admin or App Manager). The workflow writes the key to a temporary file and deletes it when the step ends. The build number is `github.run_number`; the marketing version stays 1.0.

The bundle id is `app.basayin.BasAyin`. App Store Connect needs an app record with that id before an upload can be processed. The workflow does not create the record.

## Continuous integration

`.github/workflows/ios.yml` first runs a short Linux job: `scripts/build_data.py --validate-only` on the bundled database (licence, Hebrew-only text, section order, verse headings, calendar coverage, the "this week" rule on known dates, the search index), and a check that the file matches the checksum in `data/manifest.json`. The Mac build waits for it.

The Mac job builds with Xcode 26 on `macos-26`, with signing off, and runs the unit and UI tests on an iPhone 17 Pro Max simulator. On `main`, and when started by hand, it also captures the App Store screenshots on an iPhone 17 Pro (1206×2622) and a 13-inch iPad Pro (2064×2752) and uploads them as artifacts:

- `simulator-screenshots`: home and a book's section list, light and dark.
- `app-store-screenshots`: Hebrew UI at 1206×2622, 1320×2868, and 2064×2752: home, this week's reading, a section list, the reader, search, and settings, with alpha removed.

`.github/workflows/walkthrough.yml` taps through every screen in Hebrew and English, light and dark, and at the largest text size, and uploads a screen recording and numbered screenshots.

## Screens

- **Home.** Resume, history, this week's reading, search, the five books, festivals and special Shabbatot, likkutim and responsa, settings, help, and about. A dark blue bar with the app mark, share, and favourites.
- **Book.** The sections of that book in the order of the edition. Festival derashot appear where the book prints them (חנוכה in בראשית, פורים in שמות, and so on).
- **Festivals and special Shabbatot.** The 17 festival and special-Shabbat sections together, from ערב ראש השנה to שבועות.
- **Likkutim and responsa.** The two sections at the end of the book.
- **Reading.** One section, or several when the week joins them, paragraph by paragraph. The first word of each paragraph is bold, as in the edition. When a paragraph opens a derush by quoting a verse, the verse's reference appears above it (181 places). דרוש לפרשת שקלים and פרשת פרה are one-line pointers in the edition; the reader adds a button to כי תשא and חקת, where those derashot are printed. A star saves a paragraph. A long press copies or shares the Hebrew text with its reference and the source.
- **This week.** The coming Shabbat (today, on Shabbat) using the Israel or Diaspora table from Settings: the parasha, combined parshiyot together, the special Shabbat, and every festival with a day (or its eve) between today and that Shabbat: Rosh HaShanah, Yom Kippur, Sukkot, Shemini Atzeret, Simchat Torah (וזאת הברכה), Chanukah, Purim, Pesach (with the Shabbat Chol HaMoed derashot on that Shabbat), and Shavuot. A festival that ended earlier in the week is not shown again.
- **Search.** Offline full-text search. Abbreviations match with or without quote marks (חז״ל, חז"ל and חזל). A result shows the section, the paragraph, and a snippet, and opens that place.
- **Resume and history.** The last paragraph, and recently read sections.
- **Settings.** Interface language (Hebrew or English), Israel or Diaspora, type size (the in-app slider and the system text size), light, dark, or system appearance, and the privacy policy. The edition is unpointed, so there is no nikud setting.
- **About.** The book and its author, the sources, the licences with links, and the privacy policy.

## How sections map to weeks

Bas Ayin has a section for most parshiyot, and some joined sections: ויקהל פקודי, דרוש לפרשת בהר ובחקותי, and מטות מסעי. A section belongs to a week when every parasha it covers is read that week. A parasha with no section of its own (פקודי, מטות) takes the joined section. So Vayakhel-Pekudei shows ויקהל and ויקהל פקודי; Pekudei alone shows ויקהל פקודי; Matot-Masei shows מטות מסעי and מסעי; Behar-Bechukotai shows all three of its sections.

## Data pipeline

`scripts/build_data.py` uses only the Python standard library (3.11+). It downloads the sources, checks each licence and version title, and writes:

- `BasAyin/BasAyin/Resources/bas_ayin.sqlite`: the bundled database, including an FTS5 search index without tags or quote marks
- `data/manifest.json`: counts, licences, and a checksum

```bash
python3 scripts/build_data.py
python3 scripts/build_data.py --validate-only
```

`--year-start` and `--year-end` default to 2025 through 2045. Downloads are cached in `scripts/.cache/` (not part of the app); delete it to force a fresh download. `--index-only` rebuilds the search index without downloading.

Paragraph ids are `section × 1000 + paragraph`, where sections are numbered 1–74 in the order of the edition. The script refuses to build if Sefaria's sections change order or name, so favourites and the resume place keep pointing at the same paragraph.

### What is downloaded

| Data | Version | Licence | Bundled |
| --- | --- | --- | --- |
| Bat Ayin, Hebrew | `Jerusalem, 2001` (source: National Library of Israel) | CC BY-NC 4.0 | Yes |
| Bat Ayin index | Sefaria index, for the order and Hebrew names of the 74 sections | — | Names only |
| Genesis–Deuteronomy, Hebrew | `Tanach with Text Only` | Public Domain | No, only used to check verse headings |
| Shabbat parasha, special Shabbatot, festivals | Hebcal REST API, Israel (`i=on`) and Diaspora (`i=off`) | CC BY 4.0 | Yes |

The script refuses any Bat Ayin file whose `versionTitle` or `license` is not exactly the pair above. It never requests the partial English community translation.

A verse heading is added only when a paragraph opens with a quotation followed by a Torah citation, such as `וישב יעקב בארץ מגורי אביו וגו' (לז א)`, and the first words of the quotation are found in that verse (or the next ones) of the Torah text. Inside its own book the edition omits the book name, so the section's book is used.

## Licences and attribution

- Text: Bat Ayin, Hebrew version `Jerusalem, 2001`, published by [Sefaria](https://www.sefaria.org/Bat_Ayin) under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). Non-commercial use only.
- Reading calendar: [Hebcal.com](https://www.hebcal.com), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Attribute the schedule to Hebcal.com.
- Typeface: Noto Serif Hebrew, © 2022 The Noto Project Authors, [SIL Open Font License 1.1](BasAyin/BasAyin/Resources/Fonts/OFL.txt).

## Privacy and support pages

`docs/index.html` is the support page, in Hebrew and English, and `docs/privacy/index.html` the privacy policy: the app collects no data, has no analytics, and makes no network request of its own. The in-app links point at:

- https://dberrebi.github.io/BasAyiniOS/
- https://dberrebi.github.io/BasAyiniOS/privacy/

Those URLs work after GitHub Pages is enabled for the repository (Settings → Pages → Deploy from a branch → `main` → `/docs`). `docs/app-store-listing.md` is a store-listing draft and is excluded from the Pages site.

## Not included

No signing team is stored in the project. There is no in-app payment, and there must not be one while the text is CC BY-NC. Readings outside 2025–2045 need a new run of the data script.
