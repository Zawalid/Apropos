import ApplicationServices
import Foundation
import Testing

@testable import Apropos

@Suite("AXMenuReader.element")
struct AXElementCastTests {
    @Test func acceptsAnAccessibilityElement() {
        let element = AXUIElementCreateApplication(getpid())
        #expect(AXMenuReader.element(element) != nil)
    }

    @Test func rejectsOtherObjects() {
        #expect(AXMenuReader.element("title" as NSString) == nil)
        #expect(AXMenuReader.element(NSNumber(value: 3)) == nil)
        #expect(AXMenuReader.element(NSArray()) == nil)
    }
}
