# LocalizationTools

LocalizationTools is a Swift CLI that automates localization workflows for Mozilla iOS projects (Firefox/Focus iOS). It handles exporting strings from Xcode projects to XLIFF format for translation, and importing translated XLIFF files back into projects.

## Build and Run Commands

```bash
# Build
swift build

# Run tests
swift test

# Run the CLI (after building)
./.build/debug/LocalizationTools --project-path /path/to/Client.xcodeproj --l10n-project-path /path/to/l10n/repo --export
./.build/debug/LocalizationTools --project-path /path/to/Client.xcodeproj --l10n-project-path /path/to/l10n/repo --import

# Single locale operation
./.build/debug/LocalizationTools --project-path /path/to/Client.xcodeproj --l10n-project-path /path/to/l10n/repo --locale fr --import
```

## Architecture

The CLI is built with Swift ArgumentParser and organized into three task classes:

- **main.swift**: CLI entry point, argument parsing, locale discovery from l10n repo directories
- **ImportTask**: Converts XLIFF → .xcloc format, validates XML, applies locale mappings, runs `xcodebuild -importLocalizations`
- **ExportTask**: Runs `xcodebuild -exportLocalizations`, filters excluded keys, applies comment overrides from `l10n_comments.txt`, copies to l10n repo
- **CreateTemplatesTask**: Generates template XLIFF files for localization teams (strips target translations)

## Key Concepts

**Locale Mapping**: Translates between Pontoon locale codes and Xcode locale codes (e.g., `ga` ↔ `ga-IE`, `tl` ↔ `fil`, `zgh` ↔ `tzm`). Import and export have separate mapping dictionaries.

**Excluded Keys**: Keys filtered out during export (CFBundleName, CFBundleDisplayName except ActionExtension, CFBundleShortVersionString).

**Required Keys**: Keys that must have translations during import (privacy descriptions, shortcut items, WidgetIntents strings).

**l10n_comments.txt**: Optional file in project parent directory to override XLIFF comment text. Format: `KEY_ID=Comment text`
