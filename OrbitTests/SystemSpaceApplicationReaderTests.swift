import CoreGraphics
import XCTest
@testable import Orbit

final class SystemSpaceApplicationReaderTests: XCTestCase {
    func testKeepsUniqueApplicationOrderAndExcludesOrbit() {
        let owners: [CGWindowID: pid_t] = [
            10: 101,
            11: 202,
            12: 303,
            13: 202,
            14: 404
        ]

        XCTAssertEqual(
            SystemSpaceApplicationReader.processIdentifiers(
                windowIdentifiers: [10, 11, 12, 13, 14],
                excluding: 404,
                processIdentifierForWindow: { owners[$0] }
            ),
            [101, 202, 303]
        )
    }

    func testIgnoresUnknownAndInvalidWindowOwners() {
        let owners: [CGWindowID: pid_t] = [
            20: 0,
            21: -1,
            22: 505
        ]

        XCTAssertEqual(
            SystemSpaceApplicationReader.processIdentifiers(
                windowIdentifiers: [99, 20, 21, 22],
                excluding: 606,
                processIdentifierForWindow: { owners[$0] }
            ),
            [505]
        )
    }

    func testAcceptsOnlyVisibleSizedLayerZeroContentWindows() {
        let contentBounds = CGRect(x: 10, y: 20, width: 800, height: 600)

        XCTAssertTrue(
            SystemSpaceApplicationReader.isApplicationContentWindow(
                layer: 0,
                alpha: 1,
                bounds: contentBounds
            )
        )
        XCTAssertFalse(
            SystemSpaceApplicationReader.isApplicationContentWindow(
                layer: 25,
                alpha: 1,
                bounds: CGRect(x: 0, y: 0, width: 40, height: 24)
            ),
            "An app-owned menu-bar item must not make the app appear in every Space"
        )
        XCTAssertFalse(
            SystemSpaceApplicationReader.isApplicationContentWindow(
                layer: 0,
                alpha: 0,
                bounds: contentBounds
            )
        )
        XCTAssertFalse(
            SystemSpaceApplicationReader.isApplicationContentWindow(
                layer: 0,
                alpha: 1,
                bounds: .zero
            )
        )
    }

    func testBuildsOwnerMapFromExactWindowDescriptions() {
        let visibleBounds = CGRect(x: 20, y: 40, width: 900, height: 700)
        let tinyBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        let information: [[String: Any]] = [
            windowInformation(
                identifier: 70,
                processIdentifier: 701,
                layer: 0,
                alpha: 1,
                bounds: visibleBounds
            ),
            windowInformation(
                identifier: 71,
                processIdentifier: 702,
                layer: 25,
                alpha: 1,
                bounds: visibleBounds
            ),
            windowInformation(
                identifier: 72,
                processIdentifier: 703,
                layer: 0,
                alpha: 1,
                bounds: tinyBounds
            )
        ]

        XCTAssertEqual(
            SystemSpaceApplicationReader.applicationContentOwners(
                from: information
            ),
            [70: 701]
        )
    }

    private func windowInformation(
        identifier: CGWindowID,
        processIdentifier: pid_t,
        layer: Int,
        alpha: Double,
        bounds: CGRect
    ) -> [String: Any] {
        [
            kCGWindowNumber as String: NSNumber(value: identifier),
            kCGWindowOwnerPID as String: NSNumber(value: processIdentifier),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowBounds as String:
                bounds.dictionaryRepresentation as NSDictionary
        ]
    }
}
