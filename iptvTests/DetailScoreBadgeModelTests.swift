//
//  DetailScoreBadgeModelTests.swift
//  iptvTests
//
//  Created by Codex on 13.03.26.
//

import Testing
@testable import iptv

struct DetailScoreBadgeModelTests {
    @Test
    func catalogBadgeFormatsNumericRatingsToSingleDecimal() {
        let badge = DetailScoreSource.catalog.badgeModel(value: 7.84)

        #expect(badge?.sourceID == .catalog)
        #expect(badge?.label == "Rating")
        #expect(badge?.value == "7.8")
    }

    @Test
    func catalogBadgeNormalizesNumericStrings() {
        let badge = DetailScoreSource.catalog.badgeModel(text: " 8.26 ")

        #expect(badge?.value == "8.3")
    }

    @Test
    func badgeCreationIgnoresBlankValues() {
        let badge = DetailScoreSource.rottenTomatoes.badgeModel(text: "   ")

        #expect(badge == nil)
    }
}
