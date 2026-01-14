/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

/// Creates template XLIFF files for localization teams to use as a starting point.
///
/// Templates are based on the en-US XLIFF but with target translations and
/// target-language attributes removed. This provides translators with a clean
/// file containing only source strings and notes.
struct CreateTemplatesTask {
    let l10nRepoPath: String

    /// Copies the en-US XLIFF file to the templates directory.
    /// - Throws: `LocalizationError` if file operations fail
    private func copyEnLocaleToTemplates() throws {
        let source = URL(fileURLWithPath: "\(l10nRepoPath)/en-US/firefox-ios.xliff")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("temp.xliff")
        let destination = URL(fileURLWithPath: "\(l10nRepoPath)/templates/firefox-ios.xliff")

        do {
            try FileManager.default.copyItem(at: source, to: tmp)
        } catch {
            throw LocalizationError.fileCopyFailed(source: source.path, destination: tmp.path, underlyingError: error)
        }

        do {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: tmp)
        } catch {
            throw LocalizationError.fileReplaceFailed(path: destination.path, underlyingError: error)
        }
    }

    /// Removes target-language attributes and target elements from the template XLIFF.
    ///
    /// This transforms the file from a completed translation to a blank template:
    /// - Removes `target-language` attribute from each `<file>` element
    /// - Removes all `<target>` elements, leaving only `<source>` and `<note>`
    /// - Throws: `LocalizationError` if XML parsing or file operations fail
    private func handleXML() throws {
        let url = URL(fileURLWithPath: "\(l10nRepoPath)/templates/firefox-ios.xliff")

        let xml: XMLDocument
        do {
            xml = try XMLDocument(contentsOf: url, options: .nodePreserveWhitespace)
        } catch {
            throw LocalizationError.xmlParsingFailed(path: url.path, underlyingError: error)
        }

        guard let root = xml.rootElement() else { return }

        do {
            try root.nodes(forXPath: "file").forEach { node in
                guard let node = node as? XMLElement else { return }
                node.removeAttribute(forName: "target-language")
            }
        } catch {
            throw LocalizationError.xpathQueryFailed(xpath: "file", underlyingError: error)
        }

        do {
            try root.nodes(forXPath: "file/body/trans-unit/target").forEach { $0.detach() }
        } catch {
            throw LocalizationError.xpathQueryFailed(xpath: "file/body/trans-unit/target", underlyingError: error)
        }

        do {
            try xml.xmlString.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw LocalizationError.fileWriteFailed(path: url.path, underlyingError: error)
        }
    }

    /// Executes the template creation task.
    /// - Throws: `LocalizationError` if any step fails
    func run() throws {
        try copyEnLocaleToTemplates()
        try handleXML()
    }
}
