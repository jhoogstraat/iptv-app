//
//  XtreamServiceTests.swift
//  iptvTests
//
//  Created by Codex on 05.03.26.
//

import Foundation
import Testing
@testable import iptv

struct XtreamServiceTests {
    @Test
    func getPlayURLNormalizesVodPathToMovie() {
        let service = XtreamService(
            .shared,
            baseURL: URL(string: "https://example.com/player_api.php")!,
            username: "demo-user",
            password: "demo-pass"
        )

        let url = service.getPlayURL(
            for: 42,
            type: XtreamContentType.vod.rawValue,
            containerExtension: "mkv"
        )

        #expect(url.absoluteString == "https://example.com/movie/demo-user/demo-pass/42.mkv")
    }
}
