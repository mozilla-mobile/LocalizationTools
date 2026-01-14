/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

/// Creates template xliff files for localization teams to use as a starting point.
///
/// Templates are based on the en-US xliff but with target translations and
/// target-language attributes removed. This provides translators with a clean
/// file containing only source strings and notes.
struct CreateTemplatesTask {
    let l10nRepoPath: String

    /// Copies the en-US xliff file to the templates directory.
    private func copyEnLocaleToTemplates() {
        let source = URL(fileURLWithPath: "\(l10nRepoPath)/en-US/firefox-ios.xliff")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("temp.xliff")
        let destination = URL(fileURLWithPath: "\(l10nRepoPath)/templates/firefox-ios.xliff")
        try! FileManager.default.copyItem(at: source, to: tmp)
        _ = try! FileManager.default.replaceItemAt(destination, withItemAt: tmp)
    }

    /// Removes target-language attributes and target elements from the template xliff.
    ///
    /// This transforms the file from a completed translation to a blank template:
    /// - Removes `target-language` attribute from each `<file>` element
    /// - Removes all `<target>` elements, leaving only `<source>` and `<note>`
    private func handleXML() throws {
        let url = URL(fileURLWithPath: "\(l10nRepoPath)/templates/firefox-ios.xliff")
        let xml = try! XMLDocument(contentsOf: url, options: .nodePreserveWhitespace)

        guard let root = xml.rootElement() else { return }

        try root.nodes(forXPath: "file").forEach { node in
            guard let node = node as? XMLElement else { return }
            node.removeAttribute(forName: "target-language")
        }

        try root.nodes(forXPath: "file/body/trans-unit/target").forEach { $0.detach() }
        try xml.xmlString.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Executes the template creation task.
    func run() {
        copyEnLocaleToTemplates()
        try! handleXML()
    }
}
