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
}
