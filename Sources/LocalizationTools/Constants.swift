/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

/// Shared constants used across localization tasks.
enum LocalizationConstants {
    /// Translation keys that should be excluded from localization.
    ///
    /// These keys are removed during both export and import:
    /// - `CFBundleName`: App bundle name (should not be localized)
    /// - `CFBundleDisplayName`: App display name (except for ActionExtension)
    /// - `CFBundleShortVersionString`: Version string (should not be localized)
    static let excludedTranslations: Set<String> = [
        "CFBundleName",
        "CFBundleDisplayName",
        "CFBundleShortVersionString",
    ]

    /// Additional translation keys excluded only during export.
    ///
    /// - `1Password Fill Browser Action`: Specific exclusion for 1Password integration
    static let exportOnlyExcludedTranslations: Set<String> = [
        "1Password Fill Browser Action"
    ]

    /// All excluded translations for export operations.
    static var allExportExcludedTranslations: Set<String> {
        excludedTranslations.union(exportOnlyExcludedTranslations)
    }

    /// Translation keys that must have a target value during import.
    ///
    /// If these keys are missing a translation, the source (English) text is used as fallback.
    /// This prevents app crashes and App Store rejections.
    ///
    /// Categories:
    /// - Privacy permission strings (required by iOS, app crashes without them)
    /// - Home screen shortcuts
    /// - WidgetKit intent strings (required for App Store)
    static let requiredTranslations: Set<String> = [
        // Privacy permission strings (Client/Info.plist)
        "NSCameraUsageDescription",
        "NSLocationWhenInUseUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSPhotoLibraryAddUsageDescription",

        // Home screen shortcuts
        "ShortcutItemTitleNewPrivateTab",
        "ShortcutItemTitleNewTab",
        "ShortcutItemTitleQRCode",

        // WidgetKit intent strings (WidgetKit/en-US.lproj/WidgetIntents.strings)
        // These are auto-generated IDs from Xcode's intent definition compiler
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

    /// Temporary directory path for xcodebuild export operations.
    static let exportBasePath = "/tmp/ios-localization"

    /// The XLIFF filename used in the l10n repository.
    static let xliffFilename = "firefox-ios.xliff"

    /// Checks if a file path represents an ActionExtension InfoPlist file.
    ///
    /// CFBundleDisplayName is allowed in ActionExtension files as an exception
    /// to the general exclusion rule.
    ///
    /// - Parameter fileOriginal: The "original" attribute from an XLIFF file node
    /// - Returns: `true` if this is an ActionExtension InfoPlist file
    static func isActionExtensionFile(_ fileOriginal: String) -> Bool {
        return fileOriginal.contains("Extensions/ActionExtension") &&
               fileOriginal.contains("InfoPlist.strings")
    }

    /// Determines if a translation should be excluded based on its ID and context.
    ///
    /// - Parameters:
    ///   - translationId: The translation unit ID
    ///   - isActionExtensionFile: Whether this translation is in an ActionExtension file
    ///   - excludedSet: The set of excluded translation IDs to check against
    /// - Returns: `true` if the translation should be excluded
    static func shouldExcludeTranslation(
        _ translationId: String?,
        isActionExtensionFile: Bool,
        excludedSet: Set<String>
    ) -> Bool {
        guard let id = translationId else { return false }

        // Allow CFBundleDisplayName in ActionExtension files
        if id == "CFBundleDisplayName" && isActionExtensionFile {
            return false
        }

        return excludedSet.contains(id)
    }
}
