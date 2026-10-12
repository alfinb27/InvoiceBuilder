import XCTest

extension XCUIApplication {
    /// Opens the builder's "Add an item" sheet and returns `item`'s row on its "My saved items" tab (a seeded business
    /// has saved items, so the sheet opens there). Right after the client picker closes, the button can still be
    /// under the closing sheet, or a tap can land during the dismissal and be dropped (seen on CI's iOS 27
    /// simulator), so this waits for the button to be tappable, scrolls it into view, and taps again if the sheet
    /// hasn't appeared.
    @MainActor
    @discardableResult
    func openAddItem(showing item: String = "Website development") -> XCUIElement {
        let addItem = buttons["addItem"]
        let row = buttons["catalogItem-\(item)"]
        for _ in 0..<3 {
            let tappable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isHittable == true"),
                                                     object: addItem)
            if XCTWaiter().wait(for: [tappable], timeout: 3) != .completed {
                var swipes = 0
                while !(addItem.exists && addItem.isHittable) && swipes < 8 {
                    swipeUp(velocity: .slow)
                    swipes += 1
                }
            }
            addItem.tap()
            if row.waitForExistence(timeout: 4) { return row }
        }
        XCTFail("The Add an item sheet didn't open on the saved items")
        return row
    }

    /// Picks a client in the builder's client picker by the start of its name.
    @MainActor
    func chooseClient(_ name: String) {
        XCTAssertTrue(buttons["chooseClient"].waitForExistence(timeout: 5))
        buttons["chooseClient"].tap()
        let row = buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    /// Review & send, then the send button: issues the document and opens the channel (the share sheet for
    /// WhatsApp). Closes the share sheet and the PDF preview again, leaving the issued document on screen.
    @MainActor
    func reviewAndSend(file: StaticString = #filePath, line: UInt = #line) {
        buttons["reviewAndSend"].tap()
        let send = buttons["review.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 10), "Review & send didn't open", file: file, line: line)
        send.tap()
        // The preview opens with the share sheet over it; close both.
        let done = buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 15), "the PDF preview didn't open", file: file, line: line)
        let shareClose = otherElements["ActivityListView"].buttons["Close"].firstMatch
        if shareClose.waitForExistence(timeout: 5) {
            shareClose.tap()
        } else if buttons["Close"].firstMatch.waitForExistence(timeout: 2) {
            buttons["Close"].firstMatch.tap()
        }
        if done.waitForExistence(timeout: 5) { done.tap() }
    }
}
