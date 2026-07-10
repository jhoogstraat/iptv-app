import Testing

@testable import iptv

@MainActor
struct TabsTests {
    @Test func customizationIDsAreStableAndUnique() throws {
        let expectedIDs: [Tabs: String] = [
            .home: "com.jhoogstraat.iptv.home",
            .movies: "com.jhoogstraat.iptv.movies",
            .series: "com.jhoogstraat.iptv.series",
            .live: "com.jhoogstraat.iptv.live",
            .favorites: "com.jhoogstraat.iptv.favorites",
            .downloads: "com.jhoogstraat.iptv.downloads",
            .search: "com.jhoogstraat.iptv.search",
            .settings: "com.jhoogstraat.iptv.settings",
        ]

        #expect(Tabs.allCases.count == expectedIDs.count)
        #expect(Set(Tabs.allCases.map(\.customizationID)).count == Tabs.allCases.count)

        for tab in Tabs.allCases {
            #expect(tab.customizationID == expectedIDs[tab])
        }
    }
}
