//
//  LanguageTaggedText.swift
//  iptv
//
//  Created by Codex on 08.03.26.
//

import Foundation

struct LanguageTaggedText {
    let rawValue: String
    let trimmedValue: String
    let prefixLanguageCode: String?
    let strippedPrefixValue: String?

    private let trailingLanguageCode: String?

    init(_ rawValue: String) {
        self.rawValue = rawValue
        self.trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let match = Self.firstMatch(
            in: self.trimmedValue,
            using: Self.wrappedPrefixPattern,
            codeCaptureIndex: 1,
            remainderCaptureIndex: 2
        ) ?? Self.firstMatch(
            in: self.trimmedValue,
            using: Self.prefixPattern,
            codeCaptureIndex: 1,
            remainderCaptureIndex: 2
        ) {
            prefixLanguageCode = match.code
            strippedPrefixValue = match.remainder
            trailingLanguageCode = nil
            return
        }

        prefixLanguageCode = nil
        strippedPrefixValue = nil

        if let match = Self.firstMatch(
            in: self.trimmedValue,
            using: Self.suffixPattern,
            codeCaptureIndex: 2
        ) {
            trailingLanguageCode = match.code
        } else if let match = Self.firstMatch(
            in: self.trimmedValue,
            using: Self.exactPattern,
            codeCaptureIndex: 1
        ) {
            trailingLanguageCode = match.code
        } else {
            trailingLanguageCode = nil
        }
    }

    var languageCode: String? {
        prefixLanguageCode ?? trailingLanguageCode
    }

    var groupedDisplayName: String {
        strippedPrefixValue ?? trimmedValue
    }
}

extension Category {
    var languageGroupCode: String? {
        LanguageTaggedText(name).prefixLanguageCode
    }

    var groupedDisplayName: String {
        LanguageTaggedText(name).groupedDisplayName
    }
}

private extension LanguageTaggedText {
    static let wrappedPrefixPattern = try! NSRegularExpression(
        pattern: #"^\s*\|([A-Z]{2,10})\|\s*(?:[-:]\s*)?(.+?)\s*$"#
    )
    static let prefixPattern = try! NSRegularExpression(
        pattern: #"^\s*([A-Z]{2})\s*(?:[-|:]\s*|\s+)(.+?)\s*$"#
    )
    static let suffixPattern = try! NSRegularExpression(
        pattern: #"^\s*(.+?)(?:\s*[-|:]\s*|\s+)([A-Z]{2})\s*$"#
    )
    static let exactPattern = try! NSRegularExpression(
        pattern: #"^\s*([A-Z]{2})\s*$"#
    )

    struct Match {
        let code: String
        let remainder: String?
    }

    static func firstMatch(
        in value: String,
        using expression: NSRegularExpression,
        codeCaptureIndex: Int,
        remainderCaptureIndex: Int? = nil
    ) -> Match? {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let result = expression.firstMatch(in: value, options: [], range: range) else {
            return nil
        }

        let codeRange = result.range(at: codeCaptureIndex)
        guard let codeSubstringRange = Range(codeRange, in: value) else {
            return nil
        }

        let code = String(value[codeSubstringRange]).uppercased()

        let remainder: String?
        if let remainderCaptureIndex,
           result.numberOfRanges > remainderCaptureIndex,
           let remainderRange = Range(result.range(at: remainderCaptureIndex), in: value) {
            let trimmedRemainder = value[remainderRange].trimmingCharacters(in: .whitespacesAndNewlines)
            remainder = trimmedRemainder.isEmpty ? nil : String(trimmedRemainder)
        } else {
            remainder = nil
        }

        return Match(code: code, remainder: remainder)
    }
}
