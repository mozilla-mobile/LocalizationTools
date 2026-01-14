/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

/// Provides bidirectional mapping between Xcode locale codes and Pontoon locale codes.
///
/// Xcode and Mozilla's Pontoon localization platform use different locale codes for some languages.
/// This utility allows converting between them in either direction.
///
/// Example mappings:
/// - Xcode "ga" ↔ Pontoon "ga-IE" (Irish)
/// - Xcode "fil" ↔ Pontoon "tl" (Tagalog)
/// - Xcode "tzm" ↔ Pontoon "zgh" (Tamazight)
enum LocaleMapping {
    /// Mapping from Xcode locale codes to Pontoon locale codes.
    /// These are locales where Xcode uses a shorter/different code than Pontoon.
    private static let xcodeToPontoon: [String: String] = [
        "ga": "ga-IE",
        "nb": "nb-NO",
        "nn": "nn-NO",
        "sv": "sv-SE",
        "fil": "tl",
        "sat-Olck": "sat",
    ]

    /// Mapping from Pontoon locale codes to Xcode locale codes.
    /// These are locales where Pontoon uses a different code than Xcode.
    private static let pontoonToXcode: [String: String] = [
        "ga-IE": "ga",
        "nb-NO": "nb",
        "nn-NO": "nn",
        "sv-SE": "sv",
        "tl": "fil",
        "sat": "sat-Olck",
        "zgh": "tzm",
    ]

    /// Converts an Xcode locale code to a Pontoon locale code.
    ///
    /// - Parameter xcodeLocale: The Xcode locale code (e.g., "ga", "fil")
    /// - Returns: The corresponding Pontoon locale code, or the input if no mapping exists
    static func toPontoon(_ xcodeLocale: String) -> String {
        // Special case: "en" maps to "en-US" for the l10n repository
        if xcodeLocale == "en" {
            return "en-US"
        }
        return xcodeToPontoon[xcodeLocale] ?? xcodeLocale
    }

    /// Converts a Pontoon locale code to an Xcode locale code.
    ///
    /// - Parameter pontoonLocale: The Pontoon locale code (e.g., "ga-IE", "tl")
    /// - Returns: The corresponding Xcode locale code, or the input if no mapping exists
    static func toXcode(_ pontoonLocale: String) -> String {
        return pontoonToXcode[pontoonLocale] ?? pontoonLocale
    }

    /// Returns the Pontoon locale code if a mapping exists for the given Xcode locale.
    ///
    /// Unlike `toPontoon(_:)`, this returns `nil` if no mapping exists,
    /// useful when you only want to update values that have explicit mappings.
    ///
    /// - Parameter xcodeLocale: The Xcode locale code
    /// - Returns: The Pontoon locale code if a mapping exists, `nil` otherwise
    static func pontoonMapping(forXcode xcodeLocale: String) -> String? {
        return xcodeToPontoon[xcodeLocale]
    }

    /// Returns the Xcode locale code if a mapping exists for the given Pontoon locale.
    ///
    /// Unlike `toXcode(_:)`, this returns `nil` if no mapping exists,
    /// useful when you only want to update values that have explicit mappings.
    ///
    /// - Parameter pontoonLocale: The Pontoon locale code
    /// - Returns: The Xcode locale code if a mapping exists, `nil` otherwise
    static func xcodeMapping(forPontoon pontoonLocale: String) -> String? {
        return pontoonToXcode[pontoonLocale]
    }
}
