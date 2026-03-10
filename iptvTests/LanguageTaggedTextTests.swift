//
//  LanguageTaggedTextTests.swift
//  iptvTests
//
//  Created by Codex on 08.03.26.
//

import Testing
@testable import iptv

struct LanguageTaggedTextTests {
    @Test
    func videoLanguageSupportsPrefixAndSuffixFormats() {
        let prefixed = LanguageTaggedText("EN - The Movie")
        let suffixed = LanguageTaggedText("The Movie EN")

        #expect(prefixed.languageCode == "EN")
        #expect(suffixed.languageCode == "EN")
    }

    @Test
    func categoryLanguageGroupingUsesPrefixAndStripsItFromDisplayName() {
        let category = Category(id: "1", name: "|DE| Thriller")

        #expect(category.languageGroupCode == "DE")
        #expect(category.groupedDisplayName == "Thriller")
    }

    @Test
    func categoryLanguageGroupingSupportsWrappedMultiPrefix() {
        let category = Category(id: "1", name: "|MULTI| Favorites")

        #expect(category.languageGroupCode == "MULTI")
        #expect(category.groupedDisplayName == "Favorites")
    }

    @Test
    func categoryLanguageGroupingSupportsPlainThreeLetterPrefix() {
        let category = Category(id: "1", name: "XXX Cinema")

        #expect(category.languageGroupCode == "XXX")
        #expect(category.groupedDisplayName == "Cinema")
    }

    @Test
    func categoryWithoutLanguagePrefixRemainsUngrouped() {
        let category = Category(id: "1", name: "Action")

        #expect(category.languageGroupCode == nil)
        #expect(category.groupedDisplayName == "Action")
    }
}
