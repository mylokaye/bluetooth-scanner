import Foundation

enum Proximity: String {
    case near = "Near"
    case far = "Far"
    case veryFar = "Very Far"
    case unavailable = "Unavailable"
}

struct BLEDistanceSnapshot: Hashable {
    let estimatedDistance: Double?
    let proximity: Proximity
    let confidence: Int
    let smoothedRSSI: Double?
    let isAvailable: Bool

    var distanceText: String {
        guard let estimatedDistance else { return "Unknown" }
        if estimatedDistance >= BLEDistanceEstimator.maximumDistance {
            return "20m+"
        }
        return String(format: "%.1f m", estimatedDistance)
    }
}

final class BLEDistanceEstimator {
    static let minimumDistance = 0.3
    static let maximumDistance = 20.0

    private let txPower: Double
    private let environmentalFactor: Double
    private let historyLimit: Int
    private let smoothingFactor: Double
    private let staleInterval: TimeInterval
    private let minimumDisplayInterval: TimeInterval
    private let minimumDistanceChange: Double

    private var rssiHistory: [Int] = []
    private var smoothedRSSIValue: Double?
    private var lastRSSIDate: Date?
    private var displayedDistance: Double?
    private var lastDisplayUpdateDate: Date?
    private var lastKnownGoodSnapshot: BLEDistanceSnapshot?

    init(
        txPower: Double = -59,
        environmentalFactor: Double = 2.2,
        historyLimit: Int = 10,
        smoothingFactor: Double = 0.2,
        staleInterval: TimeInterval = 5,
        minimumDisplayInterval: TimeInterval = 1,
        minimumDistanceChange: Double = 0.3
    ) {
        self.txPower = txPower
        self.environmentalFactor = environmentalFactor
        self.historyLimit = max(5, min(historyLimit, 10))
        self.smoothingFactor = smoothingFactor
        self.staleInterval = staleInterval
        self.minimumDisplayInterval = minimumDisplayInterval
        self.minimumDistanceChange = minimumDistanceChange
    }

    var estimatedDistance: Double {
        snapshot().estimatedDistance ?? BLEDistanceEstimator.maximumDistance
    }

    var proximity: Proximity {
        snapshot().proximity
    }

    var confidence: Int {
        snapshot().confidence
    }

    func update(rssi: Int) {
        update(rssi: rssi, at: Date())
    }

    func update(rssi: Int, at date: Date) {
        rssiHistory.append(rssi)
        if rssiHistory.count > historyLimit {
            rssiHistory.removeFirst(rssiHistory.count - historyLimit)
        }

        // RSSI is noisy because Bluetooth signal strength changes as radio waves bounce, absorb, and rotate around bodies and objects.
        if let smoothedRSSIValue {
            self.smoothedRSSIValue = (smoothingFactor * Double(rssi)) + ((1 - smoothingFactor) * smoothedRSSIValue)
        } else {
            smoothedRSSIValue = Double(rssi)
        }

        lastRSSIDate = date
        updateDisplayedDistanceIfNeeded(at: date)
    }

    func snapshot(at date: Date = Date()) -> BLEDistanceSnapshot {
        guard isFresh(at: date), let smoothedRSSIValue else {
            // Return the last known good snapshot while the signal is stale,
            // so the UI continues to show distance information instead of
            // immediately flipping to "Unavailable".
            if let cached = lastKnownGoodSnapshot {
                return cached
            }

            return BLEDistanceSnapshot(
                estimatedDistance: nil,
                proximity: .unavailable,
                confidence: 0,
                smoothedRSSI: self.smoothedRSSIValue,
                isAvailable: false
            )
        }

        let distance = displayedDistance ?? estimatedDistance(for: smoothedRSSIValue)
        let snapshot = BLEDistanceSnapshot(
            estimatedDistance: distance,
            proximity: proximity(for: distance),
            confidence: confidenceScore(),
            smoothedRSSI: smoothedRSSIValue,
            isAvailable: true
        )
        lastKnownGoodSnapshot = snapshot
        return snapshot
    }

    private func updateDisplayedDistanceIfNeeded(at date: Date) {
        guard let smoothedRSSIValue else { return }

        let candidateDistance = estimatedDistance(for: smoothedRSSIValue)
        guard let displayedDistance else {
            self.displayedDistance = candidateDistance
            lastDisplayUpdateDate = date
            return
        }

        let elapsed = date.timeIntervalSince(lastDisplayUpdateDate ?? .distantPast)
        let distanceDelta = abs(candidateDistance - displayedDistance)

        // Smoothing and rate limiting reduce UI flicker. Bluetooth cannot provide exact distance; walls, people, and device orientation all affect RSSI.
        guard elapsed >= minimumDisplayInterval, distanceDelta >= minimumDistanceChange else { return }

        self.displayedDistance = candidateDistance
        lastDisplayUpdateDate = date
    }

    private func estimatedDistance(for rssi: Double) -> Double {
        let rawDistance = pow(10.0, (txPower - rssi) / (10 * environmentalFactor))
        return min(max(rawDistance, BLEDistanceEstimator.minimumDistance), BLEDistanceEstimator.maximumDistance)
    }

    private func proximity(for distance: Double) -> Proximity {
        switch distance {
        case ..<2:
            return .near
        case 2 ... 6:
            return .far
        default:
            return .veryFar
        }
    }

    private func confidenceScore() -> Int {
        let standardDeviation = standardDeviation()
        let confidence = max(0, min(100, 100 - (standardDeviation * 5)))
        return Int(confidence.rounded())
    }

    private func standardDeviation() -> Double {
        guard !rssiHistory.isEmpty else { return 0 }
        let values = rssiHistory.map(Double.init)
        let average = values.reduce(0, +) / Double(values.count)
        let variance = values
            .map { pow($0 - average, 2) }
            .reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }

    private func isFresh(at date: Date) -> Bool {
        guard let lastRSSIDate else { return false }
        return date.timeIntervalSince(lastRSSIDate) <= staleInterval
    }
}
