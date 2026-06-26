import XCTest
@testable import BluetoothScanner

final class BLEDistanceEstimatorTests: XCTestCase {
    func testStableSignalProducesNearDistanceAndHighConfidence() {
        let estimator = BLEDistanceEstimator()
        let start = Date(timeIntervalSince1970: 1_000)

        for offset in 0..<8 {
            estimator.update(rssi: -59, at: start.addingTimeInterval(Double(offset)))
        }

        let snapshot = estimator.snapshot(at: start.addingTimeInterval(8))
        XCTAssertEqual(snapshot.proximity, .near)
        XCTAssertEqual(snapshot.confidence, 100)
        XCTAssertEqual(snapshot.distanceText, "1.0 m")
    }

    func testMovingAwayIncreasesDistanceAndEventuallyBecomesVeryFar() {
        let estimator = BLEDistanceEstimator()
        let start = Date(timeIntervalSince1970: 2_000)
        [-59, -65, -72, -78, -84, -88].enumerated().forEach { offset, rssi in
            estimator.update(rssi: rssi, at: start.addingTimeInterval(Double(offset)))
        }

        let snapshot = estimator.snapshot(at: start.addingTimeInterval(6))
        XCTAssertEqual(snapshot.proximity, .veryFar)
        XCTAssertGreaterThan(snapshot.estimatedDistance ?? 0, 6)
        XCTAssertLessThan(snapshot.confidence, 100)
    }

    func testMovingCloserReducesDistance() {
        let estimator = BLEDistanceEstimator()
        let start = Date(timeIntervalSince1970: 3_000)
        [-85, -82, -76, -70, -64, -58].enumerated().forEach { offset, rssi in
            estimator.update(rssi: rssi, at: start.addingTimeInterval(Double(offset)))
        }

        let snapshot = estimator.snapshot(at: start.addingTimeInterval(6))
        XCTAssertEqual(snapshot.proximity, .near)
        XCTAssertLessThan(snapshot.estimatedDistance ?? 20, 2)
    }

    func testSignalLossReturnsUnknownAndUnavailable() {
        let estimator = BLEDistanceEstimator()
        let start = Date(timeIntervalSince1970: 4_000)
        estimator.update(rssi: -60, at: start)

        let snapshot = estimator.snapshot(at: start.addingTimeInterval(6))
        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.proximity, .unavailable)
        XCTAssertEqual(snapshot.confidence, 0)
        XCTAssertEqual(snapshot.distanceText, "-")
    }
}

final class ProximityStabilizerTests: XCTestCase {
    func testMedianSmoothingIgnoresSingleRSSISpike() {
        let stabilizer = ProximityStabilizer(minimumUpdateInterval: 0)
        let start = Date(timeIntervalSince1970: 10_000)

        [-57, -57].enumerated().forEach { offset, rssi in
            stabilizer.update(rssi: rssi, at: start.addingTimeInterval(Double(offset)))
        }
        XCTAssertEqual(stabilizer.currentProximity(at: start.addingTimeInterval(2)), .close)

        [-57, -57, -85].enumerated().forEach { offset, rssi in
            stabilizer.update(rssi: rssi, at: start.addingTimeInterval(Double(offset + 2)))
        }

        XCTAssertEqual(stabilizer.currentProximity(at: start.addingTimeInterval(5)), .close)
    }

    func testOneStepChangeRequiresThreeConsecutiveCandidates() {
        let stabilizer = ProximityStabilizer(historyCapacity: 1, minimumUpdateInterval: 0)
        let start = Date(timeIntervalSince1970: 11_000)

        [-57, -57].enumerated().forEach { offset, rssi in
            stabilizer.update(rssi: rssi, at: start.addingTimeInterval(Double(offset)))
        }
        XCTAssertEqual(stabilizer.currentProximity(at: start.addingTimeInterval(2)), .close)

        [-66, -66].enumerated().forEach { offset, rssi in
            stabilizer.update(rssi: rssi, at: start.addingTimeInterval(Double(offset + 2)))
        }
        XCTAssertEqual(stabilizer.currentProximity(at: start.addingTimeInterval(4)), .close)

        stabilizer.update(rssi: -66, at: start.addingTimeInterval(5))
        XCTAssertEqual(stabilizer.currentProximity(at: start.addingTimeInterval(5)), .nearby)
    }

    func testLargeChangeRequiresTwoConsecutiveCandidates() {
        let stabilizer = ProximityStabilizer(historyCapacity: 1, minimumUpdateInterval: 0)
        let start = Date(timeIntervalSince1970: 12_000)

        [-57, -57].enumerated().forEach { offset, rssi in
            stabilizer.update(rssi: rssi, at: start.addingTimeInterval(Double(offset)))
        }
        XCTAssertEqual(stabilizer.currentProximity(at: start.addingTimeInterval(2)), .close)

        stabilizer.update(rssi: -76, at: start.addingTimeInterval(2))
        XCTAssertEqual(stabilizer.currentProximity(at: start.addingTimeInterval(2)), .close)

        stabilizer.update(rssi: -76, at: start.addingTimeInterval(3))
        XCTAssertEqual(stabilizer.currentProximity(at: start.addingTimeInterval(3)), .far)
    }

    func testVisibleUpdatesAreDebounced() {
        let stabilizer = ProximityStabilizer(historyCapacity: 1, minimumUpdateInterval: 2)
        let start = Date(timeIntervalSince1970: 13_000)

        [-57, -57].enumerated().forEach { offset, rssi in
            stabilizer.update(rssi: rssi, at: start.addingTimeInterval(Double(offset)))
        }
        XCTAssertEqual(stabilizer.currentProximity(at: start.addingTimeInterval(1)), .close)

        stabilizer.update(rssi: -76, at: start.addingTimeInterval(1.2))
        stabilizer.update(rssi: -76, at: start.addingTimeInterval(1.4))
        XCTAssertEqual(stabilizer.currentProximity(at: start.addingTimeInterval(1.4)), .close)

        XCTAssertEqual(stabilizer.currentProximity(at: start.addingTimeInterval(3.1)), .far)
    }

    func testBriefDetectionGapKeepsCurrentStateThenGoesOffline() {
        let stabilizer = ProximityStabilizer(historyCapacity: 1, minimumUpdateInterval: 0)
        let start = Date(timeIntervalSince1970: 14_000)

        [-57, -57].enumerated().forEach { offset, rssi in
            stabilizer.update(rssi: rssi, at: start.addingTimeInterval(Double(offset)))
        }

        XCTAssertEqual(stabilizer.currentProximity(at: start.addingTimeInterval(7)), .close)
        XCTAssertEqual(stabilizer.currentProximity(at: start.addingTimeInterval(10)), .offline)
    }
}
