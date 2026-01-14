/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

/// Generates the contents.json manifest required inside an .xcloc bundle.
/// - Parameter targetLocale: The Xcode locale code (e.g., "fr", "ga-IE")
/// - Returns: JSON string conforming to Apple's xcloc manifest format
private let generateManifest: (String) -> String = { targetLocale in
    return """
            {
              "developmentRegion" : "en-US",
              "project" : "Client.xcodeproj",
              "targetLocale" : "\(targetLocale)",
              "toolInfo" : {
                "toolBuildNumber" : "13A233",
                "toolID" : "com.apple.dt.xcode",
                "toolName" : "Xcode",
                "toolVersion" : "13.0"
              },
              "version" : "1.0"
            }
        """
}

/// Imports translated XLIFF files from the l10n repository into an Xcode project.
///
/// The import process involves:
/// 1. Creating .xcloc bundles (Apple's localization catalog format) from XLIFF files
/// 2. Validating and transforming the XML (locale mapping, filtering, required translations)
/// 3. Running `xcodebuild -importLocalizations` to apply translations to the project
///
/// Key behaviors:
/// - Maps Pontoon locale codes to Xcode locale codes (e.g., "ga" → "ga-IE")
/// - Removes excluded translation keys that shouldn't be localized
/// - Ensures required translations exist (falls back to source text if missing)
struct ImportTask {
    let xcodeProjPath: String
    let l10nRepoPath: String
    let locales: [String]

    private let temporaryDir = FileManager.default.temporaryDirectory.appendingPathComponent(
        "locales_to_import")

    /// Maps Pontoon locale codes to Xcode locale codes.
    /// During import, XLIFF files use Pontoon codes but Xcode expects its own codes.
    private let LOCALE_MAPPING = [
        "ga-IE": "ga",
        "nb-NO": "nb",
        "nn-NO": "nn",
        "sv-SE": "sv",
        "tl": "fil",
        "sat": "sat-Olck",
        "zgh": "tzm",
    ]

    /// Translation keys that should be removed during import (not exposed to localizers).
    private let EXCLUDED_TRANSLATIONS: Set<String> = [
        "CFBundleName", "CFBundleDisplayName", "CFBundleShortVersionString",
    ]

    /// Files where CFBundleDisplayName is allowed (exception to EXCLUDED_TRANSLATIONS).
    private let ALLOWED_CFBUNDLE_DISPLAY_NAME_FILES: Set<String> = ["ActionExtension"]

    /// Translation keys that must have a target value. If missing, the source text is used.
    /// Required for: privacy permission strings (app crashes without them), WidgetKit (App Store requirement).
    private let REQUIRED_TRANSLATIONS: Set<String> = [
        /// Client/Info.plist
        "NSCameraUsageDescription",
        "NSLocationWhenInUseUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSPhotoLibraryAddUsageDescription",
        "ShortcutItemTitleNewPrivateTab",
        "ShortcutItemTitleNewTab",
        "ShortcutItemTitleQRCode",
        /// WidgetKit/en-US.lproj/WidgetIntents.strings
        "2GqvPe",
        "ctDNmu",
        "eHmH1H",
        "eqyNJg",
        "eV8mOT",
        "fi3W24-2GqvPe",
        "fi3W24-eHmH1H",
        "fi3W24-scEmjs",
        "fi3W24-xRJbBP",
        "PzSrmZ-2GqvPe",
        "PzSrmZ-eHmH1H",
        "PzSrmZ-scEmjs",
        "PzSrmZ-xRJbBP",
        "scEmjs",
        "w9jdPK",
        "xRJbBP",
    ]

    /// Creates an .xcloc bundle from an XLIFF file in the l10n repository.
    ///
    /// An .xcloc bundle is Apple's Xcode Localization Catalog format with this structure:
    /// ```
    /// {locale}.xcloc/
    /// ├── contents.json           (manifest with project metadata)
    /// ├── Localized Contents/
    /// │   └── {locale}.xliff      (the translation file)
    /// └── Source Contents/
    ///     └── temp.txt            (placeholder for source files)
    /// ```
    ///
    /// - Parameter locale: The Pontoon locale code (e.g., "ga", "fr")
    /// - Returns: URL to the XLIFF file inside the created .xcloc bundle
    func createXcloc(locale: String) -> URL {
        let source = URL(fileURLWithPath: "\(l10nRepoPath)/\(locale)/firefox-ios.xliff")
        let locale = LOCALE_MAPPING[locale] ?? locale
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("temp.xliff")
        let destination = temporaryDir.appendingPathComponent(
            "\(locale).xcloc/Localized Contents/\(locale).xliff")
        let sourceContentsDestination = temporaryDir.appendingPathComponent(
            "\(locale).xcloc/Source Contents/temp.txt")
        let manifestDestination = temporaryDir.appendingPathComponent(
            "\(locale).xcloc/contents.json")

        let fileExists = FileManager.default.fileExists(atPath: tmp.path)
        let destinationExists = FileManager.default.fileExists(
            atPath: destination.deletingLastPathComponent().path)

        if fileExists {
            try! FileManager.default.removeItem(at: tmp)
        }

        try! FileManager.default.copyItem(at: source, to: tmp)

        if !destinationExists {
            try! FileManager.default.createDirectory(
                at: destination, withIntermediateDirectories: true)
            try! FileManager.default.createDirectory(
                at: sourceContentsDestination, withIntermediateDirectories: true)
        }

        try! generateManifest(LOCALE_MAPPING[locale] ?? locale).write(
            to: manifestDestination, atomically: true, encoding: .utf8)
        return try! FileManager.default.replaceItemAt(destination, withItemAt: tmp)!
    }

    /// Validates and transforms the XLIFF XML before import.
    ///
    /// This method performs several transformations:
    /// 1. Updates the target-language attribute to use Xcode locale codes
    /// 2. Removes excluded translation units (CFBundleName, etc.)
    /// 3. Adds fallback target elements for required translations that are missing
    /// 4. Removes empty file nodes (those with no remaining trans-units)
    ///
    /// - Parameters:
    ///   - fileUrl: Path to the XLIFF file to validate
    ///   - locale: The Pontoon locale code for this file
    func validateXml(fileUrl: URL, locale: String) {
        let xml = try! XMLDocument(contentsOf: fileUrl, options: .nodePreserveWhitespace)
        guard let root = xml.rootElement() else { return }
        let fileNodes = try! root.nodes(forXPath: "file")

        for case let fileNode as XMLElement in fileNodes {
            if let xcodeLocale = LOCALE_MAPPING[locale] {
                fileNode.attribute(forName: "target-language")?.setStringValue(
                    xcodeLocale, resolvingEntities: false)
            }

            let fileOriginal = fileNode.attribute(forName: "original")?.stringValue ?? ""
            let isActionExtensionFile =
                fileOriginal.contains("Extensions/ActionExtension")
                && fileOriginal.contains("InfoPlist.strings")

            var translations = try! fileNode.nodes(forXPath: "body/trans-unit")
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
                if translation.attribute(forName: "id")?.stringValue.map(
                    REQUIRED_TRANSLATIONS.contains) == true
                {
                    let nodes = try! translation.nodes(forXPath: "target")
                    let source = try! translation.nodes(forXPath: "source").first!.stringValue ?? ""
                    if nodes.isEmpty {
                        let element =
                            XMLNode.element(withName: "target", stringValue: source) as! XMLNode
                        translation.insertChild(element, at: 1)
                    }
                }
            }
            translations = try! fileNode.nodes(forXPath: "body/trans-unit")
            if translations.isEmpty {
                fileNode.detach()
            }
        }

        try! xml.xmlString(options: .nodePrettyPrint).write(
            to: fileUrl, atomically: true, encoding: .utf16)
    }

    /// Runs xcodebuild to import the .xcloc bundle into the Xcode project.
    /// - Parameter xclocPath: Path to the .xcloc bundle directory
    private func importLocale(xclocPath: URL) {
        let command =
            "xcodebuild -importLocalizations -project \(xcodeProjPath) -localizationPath \(xclocPath.path)"

        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", command]
        try! task.run()
        task.waitUntilExit()
    }

    /// Processes a single locale: creates xcloc, validates XML, and imports into Xcode.
    /// - Parameter locale: The Pontoon locale code to process
    private func prepareLocale(locale: String) {
        let xliffUrl = createXcloc(locale: locale)
        validateXml(fileUrl: xliffUrl, locale: locale)
        importLocale(xclocPath: xliffUrl.deletingLastPathComponent().deletingLastPathComponent())
    }

    /// Executes the import task for all configured locales.
    func run() {
        locales.forEach(prepareLocale(locale:))
    }
}
