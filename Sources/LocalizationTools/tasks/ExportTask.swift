/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

struct ExportTask {
    let xcodeProjPath: String
    let l10nRepoPath: String
    
    /// Locales here follow Pontoon's locale Key codes. If there's a difference between this and XCode's locale Key codes, adjust the `LOCALE_MAPPING` dictionary below.
    let locales: [String] = ["af",
                             "an",
                             "anp",
                             "ar",
                             "ast",
                             "az",
                             "bg",
                             "bn",
                             "bo",
                             "br",
                             "bs",
                             "ca",
                             "co",
                             "cs",
                             "cy",
                             "da",
                             "de",
                             "dsb",
                             "el",
                             "en-CA",
                             "en-GB",
                             "en",
                             "eo",
                             "es",
                             "es-AR",
                             "es-CL",
                             "es-MX",
                             "eu",
                             "fa",
                             "fi",
                             "fil",
                             "fr",
                             "ga",
                             "gd",
                             "gl",
                             "gu-IN",
                             "he",
                             "hi-IN",
                             "hr",
                             "hsb",
                             "hu",
                             "hy-AM",
                             "ia",
                             "id",
                             "is",
                             "it",
                             "ja",
                             "jv",
                             "ka",
                             "kab",
                             "kk",
                             "km",
                             "kn",
                             "ko",
                             "lo",
                             "lt",
                             "lv",
                             "ml",
                             "mr",
                             "ms",
                             "my",
                             "nb",
                             "ne-NP",
                             "nl",
                             "nn",
                             "oc",
                             "or",
                             "pa-IN",
                             "pl",
                             "pt-BR",
                             "pt-PT",
                             "rm",
                             "ro",
                             "ru",
                             "sat-Olck",
                             "ses",
                             "sk",
                             "sl",
                             "sq",
                             "su",
                             "sv",
                             "ta",
                             "te",
                             "th",
                             "tr",
                             "tt",
                             "uk",
                             "ur",
                             "uz",
                             "vi",
                             "zgh",
                             "zh-CN",
                             "zh-TW"]
    
    private let queue = DispatchQueue(label: "backgroundQueue", attributes: .concurrent)
    private let group = DispatchGroup()

    private let EXCLUDED_TRANSLATIONS: Set<String> = ["CFBundleName", "CFBundleDisplayName", "CFBundleShortVersionString", "1Password Fill Browser Action"]
    private let REQUIRED_TRANSLATIONS: Set<String> = [
        "NSCameraUsageDescription",
        "NSLocationWhenInUseUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSPhotoLibraryAddUsageDescription",
        "ShortcutItemTitleNewPrivateTab",
        "ShortcutItemTitleNewTab",
        "ShortcutItemTitleQRCode",
    ]
    
    /// This dictionary holds locale mappings between `[PontoonLocaleCode: XCodeLocaleCode]`.
    private let LOCALE_MAPPING = [
        "ga" : "ga-IE",
        "nb" : "nb-NO",
        "nn" : "nn-NO",
        "sv" : "sv-SE",
        "fil" : "tl",
        "sat-Olck" : "sat",
    ]
    
    private let EXPORT_BASE_PATH = "/tmp/ios-localization"
    
    
    private func exportLocales() {
        let command = "xcodebuild -exportLocalizations -project \(xcodeProjPath) -localizationPath \(EXPORT_BASE_PATH)"
        let command2 = locales
            .map { "-exportLanguage \($0)" }.joined(separator: " ")

        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", command + " " + command2]
        try! task.run()
        task.waitUntilExit()
    }
    
    private func handleXML(path: String, locale: String, commentOverrides: [String : String]) {
        let url = URL(fileURLWithPath: path.appending("/\(locale).xcloc/Localized Contents/\(locale).xliff"))
        let xml = try! XMLDocument(contentsOf: url, options: [.nodePreserveWhitespace, .nodeCompactEmptyElement])
        guard let root = xml.rootElement() else { return }
        let fileNodes = try! root.nodes(forXPath: "file")
        for case let fileNode as XMLElement in fileNodes {
            if let xcodeLocale = LOCALE_MAPPING[locale] {
                fileNode.attribute(forName: "target-language")?.setStringValue(xcodeLocale, resolvingEntities: false)
            }
            
            let translations = try! fileNode.nodes(forXPath: "body/trans-unit")
            for case let translation as XMLElement in translations {
                if translation.attribute(forName: "id")?.stringValue.map(EXCLUDED_TRANSLATIONS.contains) == true {
                    translation.detach()
                }
                
                if let comment = translation.attribute(forName: "id")?.stringValue.flatMap({ commentOverrides[$0] }) {
                    if let element = try? translation.nodes(forXPath: "note").first {
                        element.setStringValue(comment, resolvingEntities: true)
                    }
                }
            }
            
            let remainingTranslations = try! fileNode.nodes(forXPath: "body/trans-unit")
            
            if remainingTranslations.isEmpty {
                fileNode.detach()
            }
        }

        try! xml.xmlString.write(to: url, atomically: true, encoding: .utf8)
    }
    
    
    private func copyToL10NRepo(locale: String) {
        let source = URL(fileURLWithPath: "\(EXPORT_BASE_PATH)/\(locale).xcloc/Localized Contents/\(locale).xliff")
        let l10nLocale: String
        if locale == "en" {
            l10nLocale = "en-US"
        } else {
            l10nLocale = LOCALE_MAPPING[locale] ?? locale
        }
        let destination = URL(fileURLWithPath: "\(l10nRepoPath)/\(l10nLocale)/firefox-ios.xliff")
        _ = try! FileManager.default.replaceItemAt(destination, withItemAt: source)
    }

    
    func run() {
        exportLocales()
        let commentOverrideURL = URL(fileURLWithPath: xcodeProjPath).deletingLastPathComponent().appendingPathComponent("l10n_comments.txt")
        let commentOverrides: [String : String] = (try? String(contentsOf: commentOverrideURL))?
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String : String]()) { result, item in
                let items = item.split(separator: "=")
                guard let key = items.first, let value = items.last else { return }
                result[String(key)] = String(value)
            } ?? [:]
        
        locales.forEach { locale in
            group.enter()
            queue.async {
                handleXML(path: EXPORT_BASE_PATH, locale: locale, commentOverrides: commentOverrides)
                copyToL10NRepo(locale: locale)
                group.leave()
            }
        }
        
        group.wait()
        print(xcodeProjPath, l10nRepoPath, locales)
    }
}
