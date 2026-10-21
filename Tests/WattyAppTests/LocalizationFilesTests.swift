import XCTest

final class LocalizationFilesTests: XCTestCase {
    private static let formatSpecifier = try! NSRegularExpression(
        pattern: "%(?:[0-9]+\\$)?[-+#0]*(?:[0-9]+|\\*)?(?:\\.[0-9]+)?(?:hh|h|ll|l|q|z|t|j|L)?[@dDiuUxXoOfeEgGcCsSpaA]"
    )
    private static let pluralVariable = "%(?:[0-9]+\\$)?#@[A-Za-z_][A-Za-z0-9_]*@"
    private static let intentionallyUnchanged: Set<String> = [
        "%@ A", "%@ V", "%@ W", "%@ °C", "%@, %@", "1 h", "6 h", "24 h", "Auto", "CPU", "CPU %@", "Normal", "SoC %@"
    ]

    private let localizationRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Localization", isDirectory: true)

    private var languages: [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: localizationRoot.path)) ?? []
        return entries
            .filter { $0.hasSuffix(".lproj") }
            .map { String($0.dropLast(".lproj".count)) }
            .sorted()
    }

    private func folder(_ language: String) -> URL {
        localizationRoot.appendingPathComponent("\(language).lproj", isDirectory: true)
    }

    private func stringsFile(_ language: String) -> URL {
        folder(language).appendingPathComponent("Localizable.strings")
    }

    private func strings(_ language: String) throws -> [String: String] {
        let url = stringsFile(language)
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "\(url.path) is not a valid strings file")
    }

    private func plurals(_ language: String) throws -> [String: [String: Any]] {
        let url = folder(language).appendingPathComponent("Localizable.stringsdict")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: [String: Any]], "\(url.path) is not a valid stringsdict")
    }

    private func bundle(_ language: String) throws -> Bundle {
        try XCTUnwrap(Bundle(path: folder(language).path))
    }

    private func conversions(in text: String) -> [String] {
        var text = text.replacingOccurrences(of: "%%", with: "")
        text = text.replacingOccurrences(of: Self.pluralVariable, with: "%lld", options: .regularExpression)
        let matches = Self.formatSpecifier.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches
            .map { (text as NSString).substring(with: $0.range) }
            .map { $0.replacingOccurrences(of: "%[0-9]+\\$", with: "%", options: .regularExpression) }
            .sorted()
    }

    private func usesPositionalSpecifiers(_ text: String) -> Bool {
        let matches = Self.formatSpecifier.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let positional = matches.filter { (text as NSString).substring(with: $0.range).contains("$") }
        return !positional.isEmpty && positional.count != matches.count
    }

    func testTheEnglishAndSpanishFoldersAreFound() {
        XCTAssertTrue(languages.contains("en"))
        XCTAssertTrue(languages.contains("es"))
    }

    func testEveryLanguageShipsItsStringsFiles() {
        for language in languages {
            XCTAssertTrue(FileManager.default.fileExists(atPath: stringsFile(language).path), language)
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder(language).appendingPathComponent("Localizable.stringsdict").path), language)
        }
    }

    func testStringsFilesHaveNoDuplicateKeys() throws {
        for language in languages {
            let text = try String(contentsOf: stringsFile(language), encoding: .utf8)
            let declared = text.split(separator: "\n").filter { $0.hasPrefix("\"") }.count
            XCTAssertEqual(declared, try strings(language).count, language)
        }
    }

    func testAllLanguagesTranslateTheSameKeys() throws {
        let englishStrings = Set(try strings("en").keys)
        let englishPlurals = Set(try plurals("en").keys)
        for language in languages where language != "en" {
            XCTAssertEqual(Set(try strings(language).keys), englishStrings, language)
            XCTAssertEqual(Set(try plurals(language).keys), englishPlurals, language)
        }
    }

    func testNoKeyIsBothAStringAndAPlural() throws {
        for language in languages {
            let overlap = Set(try strings(language).keys).intersection(try plurals(language).keys)
            XCTAssertTrue(overlap.isEmpty, "\(language): \(overlap)")
        }
    }

    func testEnglishValuesAreTheirOwnKeys() throws {
        for (key, value) in try strings("en") {
            XCTAssertEqual(value, key)
        }
    }

    func testNoTranslationIsEmpty() throws {
        for language in languages {
            for (key, value) in try strings(language) {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(language): \(key)")
            }
        }
    }

    func testTranslationsKeepTheFormatSpecifiersOfTheirKey() throws {
        for language in languages {
            for (key, value) in try strings(language) {
                XCTAssertEqual(conversions(in: value), conversions(in: key), "\(language): \(key)")
                XCTAssertFalse(usesPositionalSpecifiers(value), "\(language): \(key) mixes positional and sequential specifiers")
            }
        }
    }

    func testPluralEntriesMatchTheirKeyAndDefineOneAndOther() throws {
        for language in languages {
            for (key, entry) in try plurals(language) {
                let format = try XCTUnwrap(entry["NSStringLocalizedFormatKey"] as? String, "\(language): \(key)")
                XCTAssertEqual(conversions(in: format), conversions(in: key), "\(language): \(key)")

                let variables = entry.filter { $0.key != "NSStringLocalizedFormatKey" }
                XCTAssertFalse(variables.isEmpty, "\(language): \(key)")
                for (name, value) in variables {
                    let rule = try XCTUnwrap(value as? [String: String], "\(language): \(key): \(name)")
                    XCTAssertEqual(rule["NSStringFormatSpecTypeKey"], "NSStringPluralRuleType", "\(language): \(key): \(name)")
                    XCTAssertEqual(rule["NSStringFormatValueTypeKey"], "lld", "\(language): \(key): \(name)")
                    XCTAssertNotNil(rule["one"], "\(language): \(key): \(name)")
                    XCTAssertTrue(rule["other"]?.contains("%lld") ?? false, "\(language): \(key): \(name)")
                }
            }
        }
    }

    func testSpanishIsNotLeftInEnglish() throws {
        let english = try strings("en")
        let spanish = try strings("es")
        let unchanged = Set(english.keys.filter { key in
            spanish[key]?.replacingOccurrences(of: "\u{00A0}", with: " ") == english[key]
        })

        XCTAssertEqual(unchanged, Self.intentionallyUnchanged)
    }

    func testCyclesAreCountedInTheSingularAndThePlural() throws {
        let english = try bundle("en")
        let spanish = try bundle("es")
        let en = Locale(identifier: "en_US")
        let es = Locale(identifier: "es_ES")

        XCTAssertEqual(String(localized: "\(1) cycles", bundle: english, locale: en), "1 cycle")
        XCTAssertEqual(String(localized: "\(257) cycles", bundle: english, locale: en), "257 cycles")
        XCTAssertEqual(String(localized: "\(1) cycles", bundle: spanish, locale: es), "1 ciclo")
        XCTAssertEqual(String(localized: "\(257) cycles", bundle: spanish, locale: es), "257 ciclos")
        XCTAssertEqual(String(localized: "\(0) cycles", bundle: spanish, locale: es), "0 ciclos")
    }

    func testSensorCountsAreCountedInTheSingularAndThePlural() throws {
        let english = try bundle("en")
        let spanish = try bundle("es")
        let hottest = "45.2 °C"
        let average = "38.1 °C"

        func text(_ count: Int, _ bundle: Bundle, _ locale: String) -> String {
            String(
                localized: "Hottest die sensor \(hottest) · average \(average) over \(count) sensors",
                bundle: bundle,
                locale: Locale(identifier: locale)
            )
        }

        XCTAssertEqual(text(1, english, "en_US"), "Hottest die sensor 45.2 °C · average 38.1 °C over 1 sensor")
        XCTAssertEqual(text(12, english, "en_US"), "Hottest die sensor 45.2 °C · average 38.1 °C over 12 sensors")
        XCTAssertEqual(text(1, spanish, "es_ES"), "Sensor más caliente del chip: 45.2 °C · media: 38.1 °C entre 1 sensor")
        XCTAssertEqual(text(12, spanish, "es_ES"), "Sensor más caliente del chip: 45.2 °C · media: 38.1 °C entre 12 sensores")
    }

    func testSpanishValuesKeepAnUnbreakableSpaceBeforeTheirUnit() throws {
        let spanish = try bundle("es")
        let es = Locale(identifier: "es_ES")
        let watts = "45,2"
        let seconds = 30

        XCTAssertEqual(String(localized: "\(watts) W", bundle: spanish, locale: es), "45,2\u{00A0}W")
        XCTAssertEqual(String(localized: "\(seconds) s ago", bundle: spanish, locale: es), "hace 30\u{00A0}s")
    }

    func testSpanishInfoPlistLocalizesTheCopyright() throws {
        let url = folder("es").appendingPathComponent("InfoPlist.strings")
        let values = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])

        XCTAssertTrue(try XCTUnwrap(values["NSHumanReadableCopyright"]).hasPrefix("© "))
    }
}
