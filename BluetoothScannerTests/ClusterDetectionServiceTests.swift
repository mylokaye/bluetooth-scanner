import XCTest
@testable import BluetoothScanner

final class ClusterDetectionServiceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)

    func testCorrelatedWatchJoinsPhoneGroup() {
        let service = ClusterDetectionService()
        let phone = device("phone")
        let watch = device("watch")
        let observations = observationIndex([
            observations(for: phone.id, values: [-72, -69, -66, -63, -65, -68, -71, -67]),
            observations(for: watch.id, values: [-76, -73, -70, -67, -69, -72, -75, -71])
        ])

        let result = service.detectClusters(
            devices: [phone, watch],
            observationsByDevice: observations,
            classificationsByDevice: [
                phone.id: classification(.phone),
                watch.id: classification(.watch)
            ],
            at: start.addingTimeInterval(8)
        )

        let group = result.clusters.first { $0.anchorDeviceId == phone.id }
        XCTAssertEqual(Set(group?.deviceIds ?? []), Set([phone.id, watch.id]))
        XCTAssertGreaterThan(group?.confidenceScore ?? 0, 0.55)
    }

    func testPhoneWatchAndHeadphonesFormSingleCappedGroup() {
        let service = ClusterDetectionService()
        let phone = device("phone")
        let watch = device("watch")
        let headphones = device("headphones")
        let observations = observationIndex([
            observations(for: phone.id, values: [-72, -69, -66, -63, -65, -68, -71, -67]),
            observations(for: watch.id, values: [-76, -73, -70, -67, -69, -72, -75, -71]),
            observations(for: headphones.id, values: [-78, -75, -72, -69, -71, -74, -77, -73])
        ])

        let result = service.detectClusters(
            devices: [phone, watch, headphones],
            observationsByDevice: observations,
            classificationsByDevice: [
                phone.id: classification(.phone),
                watch.id: classification(.watch),
                headphones.id: classification(.headphones)
            ],
            at: start.addingTimeInterval(8)
        )

        let group = result.clusters.first { $0.anchorDeviceId == phone.id }
        XCTAssertEqual(Set(group?.deviceIds ?? []), Set([phone.id, watch.id, headphones.id]))
        XCTAssertGreaterThan(group?.confidenceScore ?? 0, 0.85)
    }

    func testOnlyStrongestWatchJoinsPhoneGroup() {
        let service = ClusterDetectionService()
        let phone = device("phone")
        let strongWatch = device("watch-strong")
        let weakerWatch = device("watch-weaker")
        let observations = observationIndex([
            observations(for: phone.id, values: [-80, -78, -76, -74, -72, -70, -68, -66]),
            observations(for: strongWatch.id, values: [-84, -82, -80, -78, -76, -74, -72, -70]),
            observations(for: weakerWatch.id, values: [-88, -78, -78, -72, -75, -82, -71, -64])
        ])

        let result = service.detectClusters(
            devices: [phone, strongWatch, weakerWatch],
            observationsByDevice: observations,
            classificationsByDevice: [
                phone.id: classification(.phone),
                strongWatch.id: classification(.watch),
                weakerWatch.id: classification(.watch)
            ],
            at: start.addingTimeInterval(8)
        )

        let group = result.clusters.first { $0.anchorDeviceId == phone.id }
        XCTAssertEqual(Set(group?.deviceIds ?? []), Set([phone.id, strongWatch.id]))
    }

    func testOnlyStrongestHeadphonesJoinPhoneGroup() {
        let service = ClusterDetectionService()
        let phone = device("phone")
        let strongHeadphones = device("headphones-strong")
        let weakerHeadphones = device("headphones-weaker")
        let observations = observationIndex([
            observations(for: phone.id, values: [-80, -78, -76, -74, -72, -70, -68, -66]),
            observations(for: strongHeadphones.id, values: [-84, -82, -80, -78, -76, -74, -72, -70]),
            observations(for: weakerHeadphones.id, values: [-88, -78, -78, -72, -75, -82, -71, -64])
        ])

        let result = service.detectClusters(
            devices: [phone, strongHeadphones, weakerHeadphones],
            observationsByDevice: observations,
            classificationsByDevice: [
                phone.id: classification(.phone),
                strongHeadphones.id: classification(.headphones),
                weakerHeadphones.id: classification(.headphones)
            ],
            at: start.addingTimeInterval(8)
        )

        let group = result.clusters.first { $0.anchorDeviceId == phone.id }
        XCTAssertEqual(Set(group?.deviceIds ?? []), Set([phone.id, strongHeadphones.id]))
    }

    func testWearableHealthAndTrackerDoNotJoinGroups() {
        let service = ClusterDetectionService()
        let phone = device("phone")
        let wearable = device("wearable")
        let health = device("health")
        let tracker = device("tracker")
        let observations = observationIndex([
            observations(for: phone.id, values: [-72, -69, -66, -63, -65, -68, -71, -67]),
            observations(for: wearable.id, values: [-76, -73, -70, -67, -69, -72, -75, -71]),
            observations(for: health.id, values: [-77, -74, -71, -68, -70, -73, -76, -72]),
            observations(for: tracker.id, values: [-78, -75, -72, -69, -71, -74, -77, -73])
        ])

        let result = service.detectClusters(
            devices: [phone, wearable, health, tracker],
            observationsByDevice: observations,
            classificationsByDevice: [
                phone.id: classification(.phone),
                wearable.id: classification(.wearable),
                health.id: classification(.health),
                tracker.id: classification(.tracker)
            ],
            at: start.addingTimeInterval(8)
        )

        let group = result.clusters.first { $0.anchorDeviceId == phone.id }
        XCTAssertEqual(group?.deviceIds, [phone.id])
    }

    func testPhoneOnlyGroupIsReturnedWithoutConfidenceFiltering() {
        let service = ClusterDetectionService()
        let phone = device("phone")
        let observations = observationIndex([
            observations(for: phone.id, values: [-72, -69, -66, -63, -65, -68, -71, -67])
        ])

        let result = service.detectClusters(
            devices: [phone],
            observationsByDevice: observations,
            classificationsByDevice: [phone.id: classification(.phone)],
            at: start.addingTimeInterval(8)
        )

        let group = result.clusters.first { $0.anchorDeviceId == phone.id }
        XCTAssertEqual(group?.deviceIds, [phone.id])
        XCTAssertLessThan(group?.confidenceScore ?? 1, 0.4)
    }

    func testGroupsAreSortedByConfidenceDescending() {
        let service = ClusterDetectionService()
        let fullPhone = device("phone-full")
        let phoneOnly = device("phone-only")
        let watch = device("watch")
        let headphones = device("headphones")
        let observations = observationIndex([
            observations(for: fullPhone.id, values: [-72, -69, -66, -63, -65, -68, -71, -67]),
            observations(for: phoneOnly.id, values: [-45, -48, -51, -54, -52, -49, -46, -50]),
            observations(for: watch.id, values: [-76, -73, -70, -67, -69, -72, -75, -71]),
            observations(for: headphones.id, values: [-78, -75, -72, -69, -71, -74, -77, -73])
        ])

        let result = service.detectClusters(
            devices: [fullPhone, phoneOnly, watch, headphones],
            observationsByDevice: observations,
            classificationsByDevice: [
                fullPhone.id: classification(.phone),
                phoneOnly.id: classification(.phone),
                watch.id: classification(.watch),
                headphones.id: classification(.headphones)
            ],
            at: start.addingTimeInterval(8)
        )

        XCTAssertEqual(result.clusters.first?.anchorDeviceId, fullPhone.id)
        XCTAssertGreaterThanOrEqual(result.clusters.first?.confidenceScore ?? 0, result.clusters.last?.confidenceScore ?? 1)
    }

    func testRSSIClippingAndMinimumOverlapPreventAssignment() {
        let service = ClusterDetectionService()
        let phone = device("phone")
        let watch = device("watch")
        let observations = observationIndex([
            observations(for: phone.id, values: [-72, -69, -66, -63, -65, -68]),
            observations(for: watch.id, values: [-76, -73, -101, -102, -69, -72])
        ])

        let result = service.detectClusters(
            devices: [phone, watch],
            observationsByDevice: observations,
            classificationsByDevice: [
                phone.id: classification(.phone),
                watch.id: classification(.watch)
            ],
            at: start.addingTimeInterval(6)
        )

        let group = result.clusters.first { $0.anchorDeviceId == phone.id }
        XCTAssertEqual(group?.deviceIds, [phone.id])
    }

    func testStationaryPersonalDeviceIsIgnored() {
        let service = ClusterDetectionService()
        let phone = device("phone")
        let watch = device("watch")
        let observations = observationIndex([
            observations(for: phone.id, values: [-72, -69, -66, -63, -65, -68, -71, -67]),
            observations(for: watch.id, values: Array(repeating: -60, count: 8))
        ])

        let result = service.detectClusters(
            devices: [phone, watch],
            observationsByDevice: observations,
            classificationsByDevice: [
                phone.id: classification(.phone),
                watch.id: classification(.watch)
            ],
            at: start.addingTimeInterval(8)
        )

        let group = result.clusters.first { $0.anchorDeviceId == phone.id }
        XCTAssertEqual(group?.deviceIds, [phone.id])
    }

    func testDeviceAssignsToUniquelyBestPhone() {
        let service = ClusterDetectionService()
        let phoneA = device("phone-a")
        let phoneB = device("phone-b")
        let watch = device("watch")
        let observations = observationIndex([
            observations(for: phoneA.id, values: [-72, -69, -66, -63, -65, -68, -71, -67]),
            observations(for: phoneB.id, values: [-45, -48, -51, -54, -52, -49, -46, -50]),
            observations(for: watch.id, values: [-76, -73, -70, -67, -69, -72, -75, -71])
        ])

        let result = service.detectClusters(
            devices: [phoneA, phoneB, watch],
            observationsByDevice: observations,
            classificationsByDevice: [
                phoneA.id: classification(.phone),
                phoneB.id: classification(.phone),
                watch.id: classification(.watch)
            ],
            at: start.addingTimeInterval(8)
        )

        XCTAssertEqual(Set(result.clusters.first { $0.anchorDeviceId == phoneA.id }?.deviceIds ?? []), Set([phoneA.id, watch.id]))
        XCTAssertEqual(result.clusters.first { $0.anchorDeviceId == phoneB.id }?.deviceIds, [phoneB.id])
    }

    func testAssignmentRequiresThreeCyclesBeforeSwitchingPhones() {
        let service = ClusterDetectionService()
        let phoneA = device("phone-a")
        let phoneB = device("phone-b")
        let watch = device("watch")
        let classifications = [
            phoneA.id: classification(.phone),
            phoneB.id: classification(.phone),
            watch.id: classification(.watch)
        ]

        _ = service.detectClusters(
            devices: [phoneA, phoneB, watch],
            observationsByDevice: observationIndex([
                observations(for: phoneA.id, values: [-72, -69, -66, -63, -65, -68, -71, -67]),
                observations(for: phoneB.id, values: [-45, -48, -51, -54, -52, -49, -46, -50]),
                observations(for: watch.id, values: [-76, -73, -70, -67, -69, -72, -75, -71])
            ]),
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(8)
        )

        let switchedObservations = observationIndex([
            observations(for: phoneA.id, values: [-45, -48, -51, -54, -52, -49, -46, -50], offset: 60),
            observations(for: phoneB.id, values: [-72, -69, -66, -63, -65, -68, -71, -67], offset: 60),
            observations(for: watch.id, values: [-76, -73, -70, -67, -69, -72, -75, -71], offset: 60)
        ])

        let firstSwitchCycle = service.detectClusters(
            devices: [phoneA, phoneB, watch],
            observationsByDevice: switchedObservations,
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(68)
        )
        let secondSwitchCycle = service.detectClusters(
            devices: [phoneA, phoneB, watch],
            observationsByDevice: switchedObservations,
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(68)
        )
        let thirdSwitchCycle = service.detectClusters(
            devices: [phoneA, phoneB, watch],
            observationsByDevice: switchedObservations,
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(68)
        )

        XCTAssertTrue(firstSwitchCycle.clusters.first { $0.anchorDeviceId == phoneA.id }?.deviceIds.contains(watch.id) == true)
        XCTAssertTrue(secondSwitchCycle.clusters.first { $0.anchorDeviceId == phoneA.id }?.deviceIds.contains(watch.id) == true)
        XCTAssertTrue(thirdSwitchCycle.clusters.first { $0.anchorDeviceId == phoneB.id }?.deviceIds.contains(watch.id) == true)
    }

    func testSmoothedConfidenceCanIncreaseAcrossCycles() {
        let service = ClusterDetectionService()
        let phone = device("phone")
        let watch = device("watch")
        let classifications = [
            phone.id: classification(.phone),
            watch.id: classification(.watch)
        ]

        let noisyResult = service.detectClusters(
            devices: [phone, watch],
            observationsByDevice: observationIndex([
                observations(for: phone.id, values: [-80, -78, -76, -74, -72, -70, -68, -66]),
                observations(for: watch.id, values: [-88, -78, -78, -72, -75, -82, -71, -64])
            ]),
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(8)
        )
        let strongerResult = service.detectClusters(
            devices: [phone, watch],
            observationsByDevice: observationIndex([
                observations(for: phone.id, values: [-80, -78, -76, -74, -72, -70, -68, -66], offset: 30),
                observations(for: watch.id, values: [-84, -82, -80, -78, -76, -74, -72, -70], offset: 30)
            ]),
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(38)
        )

        let noisyConfidence = noisyResult.clusters.first { $0.anchorDeviceId == phone.id }?.confidenceScore ?? 0
        let strongerConfidence = strongerResult.clusters.first { $0.anchorDeviceId == phone.id }?.confidenceScore ?? 0
        XCTAssertGreaterThan(strongerConfidence, noisyConfidence)
    }

    func testOwnerGroupRequiresThreeStrongCycles() {
        let service = ClusterDetectionService()
        let watch = device("watch")
        let headphones = device("headphones")
        let observations = observationIndex([
            observations(for: watch.id, values: [-45, -43, -41, -39, -42, -44, -46, -43]),
            observations(for: headphones.id, values: [-48, -46, -44, -42, -45, -47, -49, -46])
        ])
        let classifications = [
            watch.id: classification(.watch),
            headphones.id: classification(.headphones)
        ]

        let first = service.detectClusters(
            devices: [watch, headphones],
            observationsByDevice: observations,
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(8)
        )
        let second = service.detectClusters(
            devices: [watch, headphones],
            observationsByDevice: observations,
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(8)
        )
        let third = service.detectClusters(
            devices: [watch, headphones],
            observationsByDevice: observations,
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(8)
        )

        XCTAssertNil(first.clusters.first { $0.isOwnerGroup })
        XCTAssertNil(second.clusters.first { $0.isOwnerGroup })
        XCTAssertEqual(Set(third.clusters.first { $0.isOwnerGroup }?.deviceIds ?? []), Set([watch.id, headphones.id]))
    }

    func testSingleCloseWatchCanCreateLowConfidenceOwnerGroupAfterThreeCycles() {
        let service = ClusterDetectionService()
        let watch = device("watch")
        let observations = observationIndex([
            observations(for: watch.id, values: Array(repeating: -45, count: 8))
        ])
        let classifications = [watch.id: classification(.watch)]

        let first = service.detectClusters(
            devices: [watch],
            observationsByDevice: observations,
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(8)
        )
        let second = service.detectClusters(
            devices: [watch],
            observationsByDevice: observations,
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(8)
        )
        let third = service.detectClusters(
            devices: [watch],
            observationsByDevice: observations,
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(8)
        )

        XCTAssertNil(first.clusters.first { $0.isOwnerGroup })
        XCTAssertNil(second.clusters.first { $0.isOwnerGroup })
        let ownerGroup = third.clusters.first { $0.isOwnerGroup }
        XCTAssertEqual(ownerGroup?.deviceIds, [watch.id])
        XCTAssertLessThan(ownerGroup?.confidenceScore ?? 1, 0.45)
    }

    func testSingleCloseHeadphonesCanCreateLowConfidenceOwnerGroupAfterThreeCycles() {
        let service = ClusterDetectionService()
        let headphones = device("headphones")
        let observations = observationIndex([
            observations(for: headphones.id, values: Array(repeating: -46, count: 8))
        ])
        let classifications = [headphones.id: classification(.headphones)]

        let result = ownerStableResult(
            service: service,
            devices: [headphones],
            observationsByDevice: observations,
            classificationsByDevice: classifications
        )

        let ownerGroup = result.clusters.first { $0.isOwnerGroup }
        XCTAssertEqual(ownerGroup?.deviceIds, [headphones.id])
        XCTAssertLessThan(ownerGroup?.confidenceScore ?? 1, 0.45)
    }

    func testSingleOwnerGroupConfidenceStaysBelowCorrelatedGroups() {
        let singleOwnerService = ClusterDetectionService()
        let singleWatch = device("single-watch")
        let singleOwnerObservations = observationIndex([
            observations(for: singleWatch.id, values: Array(repeating: -45, count: 8))
        ])
        let singleOwnerResult = ownerStableResult(
            service: singleOwnerService,
            devices: [singleWatch],
            observationsByDevice: singleOwnerObservations,
            classificationsByDevice: [singleWatch.id: classification(.watch)]
        )

        let ownerPairService = ClusterDetectionService()
        let ownerWatch = device("owner-watch")
        let ownerHeadphones = device("owner-headphones")
        let ownerPairObservations = observationIndex([
            observations(for: ownerWatch.id, values: [-45, -43, -41, -39, -42, -44, -46, -43]),
            observations(for: ownerHeadphones.id, values: [-48, -46, -44, -42, -45, -47, -49, -46])
        ])
        let ownerPairResult = ownerStableResult(
            service: ownerPairService,
            devices: [ownerWatch, ownerHeadphones],
            observationsByDevice: ownerPairObservations,
            classificationsByDevice: [
                ownerWatch.id: classification(.watch),
                ownerHeadphones.id: classification(.headphones)
            ]
        )

        let phoneService = ClusterDetectionService()
        let phone = device("phone")
        let phoneWatch = device("phone-watch")
        let phoneWatchResult = phoneService.detectClusters(
            devices: [phone, phoneWatch],
            observationsByDevice: observationIndex([
                observations(for: phone.id, values: [-72, -69, -66, -63, -65, -68, -71, -67]),
                observations(for: phoneWatch.id, values: [-76, -73, -70, -67, -69, -72, -75, -71])
            ]),
            classificationsByDevice: [
                phone.id: classification(.phone),
                phoneWatch.id: classification(.watch)
            ],
            at: start.addingTimeInterval(8)
        )

        let singleOwnerConfidence = singleOwnerResult.clusters.first { $0.isOwnerGroup }?.confidenceScore ?? 0
        let ownerPairConfidence = ownerPairResult.clusters.first { $0.isOwnerGroup }?.confidenceScore ?? 0
        let phoneWatchConfidence = phoneWatchResult.clusters.first { $0.anchorDeviceId == phone.id }?.confidenceScore ?? 0

        XCTAssertLessThan(singleOwnerConfidence, ownerPairConfidence)
        XCTAssertLessThan(singleOwnerConfidence, phoneWatchConfidence)
    }

    func testSingleWatchThatIsNotCloseEnoughDoesNotCreateOwnerGroup() {
        let service = ClusterDetectionService()
        let watch = device("watch")
        let observations = observationIndex([
            observations(for: watch.id, values: Array(repeating: -55, count: 8))
        ])
        let classifications = [watch.id: classification(.watch)]

        let result = ownerStableResult(
            service: service,
            devices: [watch],
            observationsByDevice: observations,
            classificationsByDevice: classifications
        )

        XCTAssertNil(result.clusters.first { $0.isOwnerGroup })
    }

    func testOwnerGroupIsCappedToOneWatchAndOneHeadphones() {
        let service = ClusterDetectionService()
        let strongWatch = device("watch-strong")
        let weakerWatch = device("watch-weaker")
        let headphones = device("headphones")
        let observations = observationIndex([
            observations(for: strongWatch.id, values: [-42, -40, -38, -36, -39, -41, -43, -40]),
            observations(for: weakerWatch.id, values: [-48, -46, -44, -42, -45, -47, -49, -46]),
            observations(for: headphones.id, values: [-44, -42, -40, -38, -41, -43, -45, -42])
        ])
        let classifications = [
            strongWatch.id: classification(.watch),
            weakerWatch.id: classification(.watch),
            headphones.id: classification(.headphones)
        ]

        _ = service.detectClusters(
            devices: [strongWatch, weakerWatch, headphones],
            observationsByDevice: observations,
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(8)
        )
        _ = service.detectClusters(
            devices: [strongWatch, weakerWatch, headphones],
            observationsByDevice: observations,
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(8)
        )
        let result = service.detectClusters(
            devices: [strongWatch, weakerWatch, headphones],
            observationsByDevice: observations,
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(8)
        )

        XCTAssertEqual(Set(result.clusters.first { $0.isOwnerGroup }?.deviceIds ?? []), Set([strongWatch.id, headphones.id]))
    }

    func testClusterIdIsStableAcrossUpdates() {
        let service = ClusterDetectionService()
        let phone = device("phone")
        let watch = device("watch")
        let observations = observationIndex([
            observations(for: phone.id, values: [-72, -69, -66, -63, -65, -68, -71, -67]),
            observations(for: watch.id, values: [-76, -73, -70, -67, -69, -72, -75, -71])
        ])
        let classifications = [
            phone.id: classification(.phone),
            watch.id: classification(.watch)
        ]

        let first = service.detectClusters(
            devices: [phone, watch],
            observationsByDevice: observations,
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(8)
        )
        let second = service.detectClusters(
            devices: [phone, watch],
            observationsByDevice: observations,
            classificationsByDevice: classifications,
            at: start.addingTimeInterval(8)
        )

        XCTAssertEqual(
            first.clusters.first { $0.anchorDeviceId == phone.id }?.id,
            second.clusters.first { $0.anchorDeviceId == phone.id }?.id
        )
    }

    private func device(_ id: String) -> BluetoothDevice {
        BluetoothDevice(
            id: id,
            displayName: id,
            advertisedName: id,
            firstSeen: start,
            lastSeen: start.addingTimeInterval(7),
            isMyDevice: false,
            localAlias: nil
        )
    }

    private func ownerStableResult(
        service: ClusterDetectionService,
        devices: [BluetoothDevice],
        observationsByDevice: [String: [ScanObservation]],
        classificationsByDevice: [String: DetectedDeviceClassification]
    ) -> ClusterDetectionResult {
        _ = service.detectClusters(
            devices: devices,
            observationsByDevice: observationsByDevice,
            classificationsByDevice: classificationsByDevice,
            at: start.addingTimeInterval(8)
        )
        _ = service.detectClusters(
            devices: devices,
            observationsByDevice: observationsByDevice,
            classificationsByDevice: classificationsByDevice,
            at: start.addingTimeInterval(8)
        )
        return service.detectClusters(
            devices: devices,
            observationsByDevice: observationsByDevice,
            classificationsByDevice: classificationsByDevice,
            at: start.addingTimeInterval(8)
        )
    }

    private func classification(_ category: DeviceCategory) -> DetectedDeviceClassification {
        DetectedDeviceClassification(
            manufacturer: nil,
            appearance: nil,
            category: category,
            likelyProduct: nil,
            confidence: 100,
            evidence: []
        )
    }

    private func observations(for deviceId: String, values: [Int], offset: TimeInterval = 0) -> [ScanObservation] {
        values.enumerated().map { index, rssi in
            ScanObservation(
                id: UUID(),
                deviceId: deviceId,
                timestamp: start.addingTimeInterval(offset + Double(index)),
                rssi: rssi,
                advertisedName: nil,
                serviceUUIDs: [],
                manufacturerDataSummary: nil,
                manufacturerIdentifier: nil,
                appearanceValue: nil,
                txPower: nil
            )
        }
    }

    private func observationIndex(_ observationGroups: [[ScanObservation]]) -> [String: [ScanObservation]] {
        Dictionary(grouping: observationGroups.flatMap { $0 }, by: \.deviceId)
    }
}
