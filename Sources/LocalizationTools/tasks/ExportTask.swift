/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

/// Exports localizable strings from an Xcode project to XLIFF files for translation.
///
/// The export process involves:
/// 1. Running `xcodebuild -exportLocalizations` to extract strings from the project
/// 2. Processing the XLIFF XML (locale mapping, filtering excluded keys, applying comment overrides)
/// 3. Copying the processed XLIFF files to the l10n repository
///
/// Processing is performed concurrently using a dispatch queue for better performance.
struct ExportTask {
    let xcodeProjPath: String
    let l10nRepoPath: String
    let locales: [String]

    /// Concurrent queue for parallel processing of multiple locales.
    private let queue = DispatchQueue(label: "backgroundQueue", attributes: .concurrent)
    private let group = DispatchGroup()

    /// Translation keys that should be removed from exports (not exposed to localizers).
    private let EXCLUDED_TRANSLATIONS: Set<String> = ["CFBundleName", "CFBundleDisplayName", "CFBundleShortVersionString", "1Password Fill Browser Action"]

    /// Files where CFBundleDisplayName is allowed (exception to EXCLUDED_TRANSLATIONS).
    private let ALLOWED_CFBUNDLE_DISPLAY_NAME_FILES: Set<String> = ["ActionExtension"]

    /// Maps Xcode locale codes to Pontoon locale codes for the l10n repository.
    /// This is the inverse of ImportTask's mapping.
    private let LOCALE_MAPPING = [
        "ga" : "ga-IE",
        "nb" : "nb-NO",
        "nn" : "nn-NO",
        "sv" : "sv-SE",
        "fil" : "tl",
        "sat-Olck" : "sat",
    ]

    /// Temporary directory where xcodebuild exports localization files.
    private let EXPORT_BASE_PATH = "/tmp/ios-localization"


    /// Runs xcodebuild to export localizations for all configured locales.
    /// Exports are written to EXPORT_BASE_PATH as .xcloc bundles.
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

    /// Processes an exported XLIFF file: filters excluded keys and applies comment overrides.
    ///
    /// - Parameters:
    ///   - path: Base path where .xcloc bundles were exported
    ///   - locale: The locale code being processed
    ///   - commentOverrides: Dictionary of translation ID → custom comment text
    private func handleXML(path: String, locale: String, commentOverrides: [String : String]) {
        let url = URL(fileURLWithPath: path.appending("/\(locale).xcloc/Localized Contents/\(locale).xliff"))
        let xml = try! XMLDocument(contentsOf: url, options: [.nodePreserveWhitespace, .nodeCompactEmptyElement])
        guard let root = xml.rootElement() else { return }
        let fileNodes = try! root.nodes(forXPath: "file")
        for case let fileNode as XMLElement in fileNodes {
            if let xcodeLocale = LOCALE_MAPPING[locale] {
                fileNode.attribute(forName: "target-language")?.setStringValue(xcodeLocale, resolvingEntities: false)
            }

            let fileOriginal = fileNode.attribute(forName: "original")?.stringValue ?? ""
            let isActionExtensionFile = fileOriginal.contains("Extensions/ActionExtension") && 
                                       fileOriginal.contains("InfoPlist.strings")
            
            let translations = try! fileNode.nodes(forXPath: "body/trans-unit")
            for case let translation as XMLElement in translations {
                let translationId = translation.attribute(forName: "id")?.stringValue
                
                let shouldExclude: Bool
                if let id = translationId, id == "CFBundleDisplayName" && isActionExtensionFile {
                    shouldExclude = false
                } else {
                    shouldExclude = translationId.map(EXCLUDED_TRANSLATIONS.contains) == true
                }
                
                if shouldExclude {
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


    /// Copies a processed XLIFF file to the l10n repository.
    ///
    /// Handles locale code mapping (e.g., "en" → "en-US", "ga" → "ga-IE") to match
    /// the directory structure expected by the l10n repository.
    ///
    /// - Parameter locale: The Xcode locale code of the file to copy
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


    /// Executes the export task: exports from Xcode, processes XML, and copies to l10n repo.
    ///
    /// Comment overrides are loaded from `l10n_comments.txt` in the project's parent directory.
    /// Format: `TRANSLATION_ID=Custom comment text` (one per line).
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
