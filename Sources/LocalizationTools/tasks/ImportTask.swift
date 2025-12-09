/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

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

struct ImportTask {
    let xcodeProjPath: String
    let l10nRepoPath: String
    let locales: [String]

    private let temporaryDir = FileManager.default.temporaryDirectory.appendingPathComponent("locales_to_import")

    /// This dictionary holds locale mappings between `[XCodeLocaleCode: PontoonLocaleCode]`.
    private let LOCALE_MAPPING = [
        "ga-IE": "ga",
        "nb-NO": "nb",
        "nn-NO": "nn",
        "sv-SE": "sv",
        "tl"   : "fil",
        "sat"  : "sat-Olck",
        "zgh"  : "tzm",
    ]

    // We don't want to expose these to our localization team
    private let EXCLUDED_TRANSLATIONS: Set<String> = ["CFBundleName", "CFBundleDisplayName", "CFBundleShortVersionString"]
    private let ALLOWED_CFBUNDLE_DISPLAY_NAME_FILES: Set<String> = ["ActionExtension"]

    // Application will crash without the IDs in Info.plist
    // App Store requires strings in WidgetKit
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

    func createXcloc(locale: String) -> URL {
        let source = URL(fileURLWithPath: "\(l10nRepoPath)/\(locale)/firefox-ios.xliff")
        let locale = LOCALE_MAPPING[locale] ?? locale
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("temp.xliff")
        let destination = temporaryDir.appendingPathComponent("\(locale).xcloc/Localized Contents/\(locale).xliff")
        let sourceContentsDestination = temporaryDir.appendingPathComponent("\(locale).xcloc/Source Contents/temp.txt")
        let manifestDestination = temporaryDir.appendingPathComponent("\(locale).xcloc/contents.json")

        let fileExists = FileManager.default.fileExists(atPath: tmp.path)
        let destinationExists = FileManager.default.fileExists(atPath: destination.deletingLastPathComponent().path)

        if fileExists {
            try! FileManager.default.removeItem(at: tmp)
        }

        try! FileManager.default.copyItem(at: source, to: tmp)

        if !destinationExists {
            try! FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try! FileManager.default.createDirectory(at: sourceContentsDestination, withIntermediateDirectories: true)
        }

        try! generateManifest(LOCALE_MAPPING[locale] ?? locale).write(to: manifestDestination, atomically: true, encoding: .utf8)
        return try! FileManager.default.replaceItemAt(destination, withItemAt: tmp)!
    }

    func validateXml(fileUrl: URL, locale: String) {
        let xml = try! XMLDocument(contentsOf: fileUrl, options: .nodePreserveWhitespace)
        guard let root = xml.rootElement() else { return }
        let fileNodes =  try! root.nodes(forXPath: "file")

        for case let fileNode as XMLElement in fileNodes {
            if let xcodeLocale = LOCALE_MAPPING[locale] {
                fileNode.attribute(forName: "target-language")?.setStringValue(xcodeLocale, resolvingEntities: false)
            }

            let fileOriginal = fileNode.attribute(forName: "original")?.stringValue ?? ""
            let isActionExtensionFile = fileOriginal.contains("Extensions/ActionExtension") && 
                                       fileOriginal.contains("InfoPlist.strings")
            
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
                if translation.attribute(forName: "id")?.stringValue.map(REQUIRED_TRANSLATIONS.contains) == true {
                    let nodes = try! translation.nodes(forXPath: "target")
                    let source = try! translation.nodes(forXPath: "source").first!.stringValue ?? ""
                    if nodes.isEmpty {
                        let element = XMLNode.element(withName: "target", stringValue: source) as! XMLNode
                        translation.insertChild(element, at: 1)
                    }
                }
            }
            translations = try! fileNode.nodes(forXPath: "body/trans-unit")
            if translations.isEmpty {
                fileNode.detach()
            }
        }

        try! xml.xmlString(options: .nodePrettyPrint).write(to: fileUrl, atomically: true, encoding: .utf16)
    }

    private func importLocale(xclocPath: URL) {
        let command = "xcodebuild -importLocalizations -project \(xcodeProjPath) -localizationPath \(xclocPath.path)"

        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", command]
        try! task.run()
        task.waitUntilExit()
    }

    private func prepareLocale(locale: String) {
        let xliffUrl = createXcloc(locale: locale)
        validateXml(fileUrl: xliffUrl, locale: locale)
        importLocale(xclocPath: xliffUrl.deletingLastPathComponent().deletingLastPathComponent())
    }

    func run() {
        locales.forEach(prepareLocale(locale:))
    }
}
