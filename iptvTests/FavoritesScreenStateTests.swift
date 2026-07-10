import Testing

@testable import iptv

@Suite("Favorites screen focus")
struct FavoritesScreenStateTests {
    @Test func removingMiddleRowFocusesFollowingRow() {
        #expect(
            FavoritesFocusProjection.successor(
                afterRemoving: 20,
                from: [10, 20, 30]
            ) == 30
        )
    }

    @Test func removingLastRowFocusesPreviousRow() {
        #expect(
            FavoritesFocusProjection.successor(
                afterRemoving: 30,
                from: [10, 20, 30]
            ) == 20
        )
    }

    @Test func removingOnlyRowReturnsFocusToScopeControl() {
        #expect(
            FavoritesFocusProjection.successor(
                afterRemoving: 10,
                from: [10]
            ) == nil
        )
    }
}
