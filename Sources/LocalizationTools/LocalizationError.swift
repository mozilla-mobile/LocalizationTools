/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

/// Errors that can occur during localization operations.
enum LocalizationError: Error, CustomStringConvertible {
    /// Failed to execute an external process (e.g., xcodebuild).
    case processExecutionFailed(command: String, underlyingError: Error)

    /// Failed to parse an XML/XLIFF file.
    case xmlParsingFailed(path: String, underlyingError: Error)

    /// Failed to query XML using XPath.
    case xpathQueryFailed(xpath: String, underlyingError: Error)

    /// Failed to write a file to disk.
    case fileWriteFailed(path: String, underlyingError: Error)

    /// Failed to read a file from disk.
    case fileReadFailed(path: String, underlyingError: Error)

    /// Failed to copy a file.
    case fileCopyFailed(source: String, destination: String, underlyingError: Error)

    /// Failed to delete a file.
    case fileDeleteFailed(path: String, underlyingError: Error)

    /// Failed to create a directory.
    case directoryCreationFailed(path: String, underlyingError: Error)

    /// Failed to replace a file.
    case fileReplaceFailed(path: String, underlyingError: Error)

    /// The XLIFF file is missing required content.
    case invalidXliffStructure(path: String, details: String)

    /// Failed to list directory contents.
    case directoryListingFailed(path: String, underlyingError: Error)

    var description: String {
        switch self {
        case .processExecutionFailed(let command, let error):
            return "Failed to execute process '\(command)': \(error.localizedDescription)"
        case .xmlParsingFailed(let path, let error):
            return "Failed to parse XML file at '\(path)': \(error.localizedDescription)"
        case .xpathQueryFailed(let xpath, let error):
            return "Failed to execute XPath query '\(xpath)': \(error.localizedDescription)"
        case .fileWriteFailed(let path, let error):
            return "Failed to write file at '\(path)': \(error.localizedDescription)"
        case .fileReadFailed(let path, let error):
            return "Failed to read file at '\(path)': \(error.localizedDescription)"
        case .fileCopyFailed(let source, let destination, let error):
            return "Failed to copy file from '\(source)' to '\(destination)': \(error.localizedDescription)"
        case .fileDeleteFailed(let path, let error):
            return "Failed to delete file at '\(path)': \(error.localizedDescription)"
        case .directoryCreationFailed(let path, let error):
            return "Failed to create directory at '\(path)': \(error.localizedDescription)"
        case .fileReplaceFailed(let path, let error):
            return "Failed to replace file at '\(path)': \(error.localizedDescription)"
        case .invalidXliffStructure(let path, let details):
            return "Invalid XLIFF structure in '\(path)': \(details)"
        case .directoryListingFailed(let path, let error):
            return "Failed to list directory contents at '\(path)': \(error.localizedDescription)"
        }
    }
}
