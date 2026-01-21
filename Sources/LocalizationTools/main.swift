/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import ArgumentParser

/// Command-line interface for automating localization workflows in Mozilla iOS projects.
///
/// This tool provides two main operations:
/// - **Export**: Extracts localizable strings from an Xcode project to XLIFF files for translation
/// - **Import**: Imports translated XLIFF files back into the Xcode project
///
/// Locales are automatically discovered from subdirectories in the l10n repository path,
/// or a single locale can be specified with the `--locale` flag.
struct LocalizationTools: ParsableCommand {
    @Option(help: "Path to the project")
    var projectPath: String

    @Option(name: .customLong("l10n-project-path"), help: "Path to the l10n project")
    var l10nProjectPath: String

    @Option(name: .customLong("locale"), help: "Locale code for single locale import/export")
    var localeCode: String?

    @Flag(name: .customLong("export"), help: "To determine if we should run the export task.")
    var runExportTask = false

    @Flag(name: .customLong("import"), help: "To determine if we should run the import task.")
    var runImportTask = false

    @Option(name: .customLong("xliff-name"), help: "XLIFF filename (default: firefox-ios.xliff)")
    var xliffName: String = "firefox-ios.xliff"

    @Option(name: .customLong("development-region"), help: "Development region for xcloc manifest (default: en-US)")
    var developmentRegion: String = "en-US"

    @Option(name: .customLong("project-name"), help: "Project name for xcloc manifest (default: Client.xcodeproj)")
    var projectName: String = "Client.xcodeproj"

    @Flag(name: .customLong("skip-widget-kit"), help: "Exclude WidgetKit strings from required translations")
    var skipWidgetKit: Bool = false

    @Option(name: .customLong("export-base-path"), help: "Base path for export temp files (default: /tmp/ios-localization)")
    var exportBasePath: String = "/tmp/ios-localization"

    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "l10nTools", abstract: "Scripts for automating l10n for Mozilla iOS projects.", discussion: "", version: "1.0", shouldDisplay: true, subcommands: [], defaultSubcommand: nil, helpNames: .long)

    }

    /// Validates that exactly one task flag (--export or --import) is specified.
    /// - Returns: `true` if arguments are valid, `false` otherwise
    private func validateArguments() -> Bool {
        switch (runExportTask, runImportTask) {
        case (false, false):
            print("Please specify which task to run with --export, --import")
            return false
        case (true, true):
            print("Please choose a single task to run")
            return false
        default: return true;
        }
    }

    /// Main entry point that orchestrates the localization workflow.
    ///
    /// Discovers locales from the l10n repository (or uses a single specified locale),
    /// then executes the requested import or export task.
    mutating func run() throws {
        guard validateArguments() else { Self.exit() }

        var locales: [String]

        if localeCode != nil {
            locales = [ localeCode! ]
        } else {
            do {
                let directoryContent = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: l10nProjectPath), includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                let folders = directoryContent.filter{ $0.hasDirectoryPath }
                locales = []
                for f in folders {
                    locales.append(f.pathComponents.last!)
                }
                locales = locales.filter{ $0 != "templates" }
                locales.sort()
            } catch {
                throw LocalizationError.directoryListingFailed(path: l10nProjectPath, underlyingError: error)
            }
        }

        if runImportTask {
            try ImportTask(
                xcodeProjPath: projectPath,
                l10nRepoPath: l10nProjectPath,
                locales: locales,
                xliffName: xliffName,
                developmentRegion: developmentRegion,
                projectName: projectName,
                skipWidgetKit: skipWidgetKit
            ).run()
        }

        if runExportTask {
            try ExportTask(
                xcodeProjPath: projectPath,
                l10nRepoPath: l10nProjectPath,
                locales: locales,
                xliffName: xliffName,
                exportBasePath: exportBasePath
            ).run()
            /// Don't extract templates if only one locale was requested
            if localeCode == nil {
                try CreateTemplatesTask(l10nRepoPath: l10nProjectPath, xliffName: xliffName).run()
            }
        }
    }
}

do {
    var command = try LocalizationTools.parseAsRoot()
    try command.run()
} catch let error as LocalizationError {
    print("Error: \(error)")
    LocalizationTools.exit(withError: error)
} catch {
    LocalizationTools.exit(withError: error)
}
