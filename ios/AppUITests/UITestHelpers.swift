import XCTest

extension XCUIApplication {
    /// Opens the builder's catalogue picker ("Add from items") and returns `item`'s row in it. Right after the client
    /// picker closes, the button can still be under the closing sheet, or a tap can land during the dismissal and be
    /// dropped (seen on CI's iOS 27 simulator), so this waits for the button to be tappable, scrolls it into view,
    /// and taps again if the list hasn't appeared.
    @MainActor
    @discardableResult
    func openCatalogue(showing item: String = "Website development") -> XCUIElement {
        let addFromItems = buttons["addFromItems"]
        let row = buttons["catalogItem-\(item)"]
        for _ in 0..<3 {
            let tappable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isHittable == true"),
                                                     object: addFromItems)
            if XCTWaiter().wait(for: [tappable], timeout: 3) != .completed {
                var swipes = 0
                while !(addFromItems.exists && addFromItems.isHittable) && swipes < 8 {
                    swipeUp(velocity: .slow)
                    swipes += 1
                }
            }
            addFromItems.tap()
            if row.waitForExistence(timeout: 4) { return row }
        }
        XCTFail("The catalogue picker didn't open")
        return row
    }
}
