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

    /// Runs xcodebuild to export localizations for all configured locales.
    /// Exports are written to the temporary export path as .xcloc bundles.
    /// - Throws: `LocalizationError.processExecutionFailed` if xcodebuild fails to start
    private func exportLocales() throws {
        let exportPath = LocalizationConstants.exportBasePath
        let command = "xcodebuild -exportLocalizations -project \(xcodeProjPath) -localizationPath \(exportPath)"
        let command2 = locales.map { "-exportLanguage \($0)" }.joined(separator: " ")

        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", command + " " + command2]
        do {
            try task.run()
        } catch {
            throw LocalizationError.processExecutionFailed(
                command: "xcodebuild -exportLocalizations",
                underlyingError: error
            )
        }
        task.waitUntilExit()
    }

    /// Processes an exported XLIFF file: filters excluded keys and applies comment overrides.
    ///
    /// - Parameters:
    ///   - path: Base path where .xcloc bundles were exported
    ///   - locale: The locale code being processed
    ///   - commentOverrides: Dictionary of translation ID → custom comment text
    /// - Throws: `LocalizationError` if XML parsing, XPath queries, or file writing fails
    private func handleXML(
        path: String,
        locale: String,
        commentOverrides: [String: String]
    ) throws {
        let url = URL(fileURLWithPath: path.appending("/\(locale).xcloc/Localized Contents/\(locale).xliff"))

        let xml: XMLDocument
        do {
            xml = try XMLDocument(contentsOf: url, options: [.nodePreserveWhitespace, .nodeCompactEmptyElement])
        } catch {
            throw LocalizationError.xmlParsingFailed(path: url.path, underlyingError: error)
        }

        guard let root = xml.rootElement() else { return }

        let fileNodes: [XMLNode]
        do {
            fileNodes = try root.nodes(forXPath: "file")
        } catch {
            throw LocalizationError.xpathQueryFailed(xpath: "file", underlyingError: error)
        }

        for case let fileNode as XMLElement in fileNodes {
            // Update target-language if this locale has a Pontoon mapping
            if let pontoonLocale = LocaleMapping.pontoonMapping(forXcode: locale) {
                fileNode.attribute(forName: "target-language")?.setStringValue(pontoonLocale, resolvingEntities: false)
            }

            let fileOriginal = fileNode.attribute(forName: "original")?.stringValue ?? ""
            let isActionExtensionFile = LocalizationConstants.isActionExtensionFile(fileOriginal)

            let translations: [XMLNode]
            do {
                translations = try fileNode.nodes(forXPath: "body/trans-unit")
            } catch {
                throw LocalizationError.xpathQueryFailed(xpath: "body/trans-unit", underlyingError: error)
            }

            for case let translation as XMLElement in translations {
                let translationId = translation.attribute(forName: "id")?.stringValue

                let shouldExclude = LocalizationConstants.shouldExcludeTranslation(
                    translationId,
                    isActionExtensionFile: isActionExtensionFile,
                    excludedSet: LocalizationConstants.allExportExcludedTranslations
                )

                if shouldExclude {
                    translation.detach()
                }

                if let comment = translation.attribute(forName: "id")?.stringValue.flatMap({ commentOverrides[$0] }) {
                    if let element = try? translation.nodes(forXPath: "note").first {
                        element.setStringValue(comment, resolvingEntities: true)
                    }
                }
            }

            let remainingTranslations: [XMLNode]
            do {
                remainingTranslations = try fileNode.nodes(forXPath: "body/trans-unit")
            } catch {
                throw LocalizationError.xpathQueryFailed(xpath: "body/trans-unit", underlyingError: error)
            }

            if remainingTranslations.isEmpty {
                fileNode.detach()
            }
        }

        do {
            try xml.xmlString.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw LocalizationError.fileWriteFailed(path: url.path, underlyingError: error)
        }
    }

    /// Copies a processed XLIFF file to the l10n repository.
    ///
    /// Handles locale code mapping (e.g., "en" → "en-US", "ga" → "ga-IE") to match
    /// the directory structure expected by the l10n repository.
    ///
    /// - Parameter locale: The Xcode locale code of the file to copy
    /// - Throws: `LocalizationError.fileReplaceFailed` if the file copy fails
    private func copyToL10NRepo(locale: String) throws {
        let exportPath = LocalizationConstants.exportBasePath
        let source = URL(fileURLWithPath: "\(exportPath)/\(locale).xcloc/Localized Contents/\(locale).xliff")
        let l10nLocale = LocaleMapping.toPontoon(locale)
        let destination = URL(fileURLWithPath: "\(l10nRepoPath)/\(l10nLocale)/\(LocalizationConstants.xliffFilename)")
        do {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: source)
        } catch {
            throw LocalizationError.fileReplaceFailed(path: destination.path, underlyingError: error)
        }
    }

    /// Executes the export task: exports from Xcode, processes XML, and copies to l10n repo.
    ///
    /// Comment overrides are loaded from `l10n_comments.txt` in the project's parent directory.
    /// Format: `TRANSLATION_ID=Custom comment text` (one per line).
    ///
    /// - Throws: `LocalizationError` if any step of the export process fails
    func run() throws {
        try exportLocales()
        let commentOverrideURL = URL(fileURLWithPath: xcodeProjPath)
            .deletingLastPathComponent()
            .appendingPathComponent("l10n_comments.txt")
        let commentOverrides: [String: String] = (try? String(contentsOf: commentOverrideURL))?
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: String]()) { result, item in
                let items = item.split(separator: "=")
                guard let key = items.first, let value = items.last else { return }
                result[String(key)] = String(value)
            } ?? [:]

        // Collect errors from concurrent processing
        let errorsLock = NSLock()
        var errors: [LocalizationError] = []

        locales.forEach { locale in
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    try handleXML(
                        path: LocalizationConstants.exportBasePath,
                        locale: locale,
                        commentOverrides: commentOverrides
                    )
                    try copyToL10NRepo(locale: locale)
                } catch let error as LocalizationError {
                    errorsLock.lock()
                    errors.append(error)
                    errorsLock.unlock()
                } catch {
                    errorsLock.lock()
                    errors.append(.fileWriteFailed(path: locale, underlyingError: error))
                    errorsLock.unlock()
                }
            }
        }

        group.wait()

        // Report any errors that occurred during processing
        if !errors.isEmpty {
            for error in errors {
                print("Error: \(error)")
            }
            throw errors.first!
        }

        print(xcodeProjPath, l10nRepoPath, locales)
    }
}
