import Foundation
import SwiftUI

// MARK: - Proximity State

enum ProximityState: String, CaseIterable {
    case veryClose = "Very Close"
    case close = "Close"
    case nearby = "Nearby"
    case far = "Far"
    case veryFar = "Very Far"
    case offline = "Offline"

    /// The next state when moving further away, or nil if already at the furthest.
    var nextFurther: ProximityState? {
        switch self {
        case .veryClose: return .close
        case .close:     return .nearby
        case .nearby:    return .far
        case .far:       return .veryFar
        case .veryFar:   return .offline
        case .offline:   return nil
        }
    }

    /// The next state when moving closer, or nil if already at the closest.
    var nextCloser: ProximityState? {
        switch self {
        case .veryClose: return nil
        case .close:     return .veryClose
        case .nearby:    return .close
        case .far:       return .nearby
        case .veryFar:   return .far
        case .offline:   return .veryFar
        }
    }

    /// Display color for the proximity pill in the UI.
    var color: Color {
        switch self {
        case .veryClose: return .green
        case .close, .nearby, .far: return .orange
        case .veryFar: return .red
        case .offline: return .gray
        }
    }

    var surfaceColor: Color {
        switch self {
        case .veryClose:
            return .green.opacity(0.10)
        case .close, .nearby, .far:
            return .orange.opacity(0.11)
        case .veryFar:
            return .red.opacity(0.10)
        case .offline:
            return .gray.opacity(0.10)
        }
    }
}

// MARK: - RSSI History Store

/// A fixed-size ring buffer that stores the most recent RSSI readings for a device.
struct RSSIHistoryStore {
    private var values: [Int] = []
    private let capacity: Int

    init(capacity: Int = 7) {
        self.capacity = max(1, capacity)
    }

    var count: Int { values.count }

    /// Appends a new RSSI reading, evicting the oldest if at capacity.
    mutating func append(_ rssi: Int) {
        values.append(rssi)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }

    /// Returns the median of stored RSSI values, or nil if empty.
    func median() -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.map(Double.init).sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    /// Removes all stored readings.
    mutating func clear() {
        values.removeAll()
    }
}

// MARK: - Hysteresis Thresholds

/// RSSI thresholds (dBm) for transitioning between proximity states.
///
/// Because RSSI is always negative, "stronger" means a less-negative number (e.g. -45 > -55).
/// "Weaker" means a more-negative number (e.g. -70 < -60).
private enum HysteresisThreshold {
    /// To leave this state moving further away, RSSI must be **weaker** (more negative) than this.
    /// e.g. Very Close → Close when RSSI < -53.
    static let leaveFurther: [ProximityState: Double] = [
        .veryClose: -53,
        .close:     -64,
        .nearby:    -74,
        .far:       -84,
        .veryFar:   -92,
        .offline:   .greatestFiniteMagnitude,  // cannot leave further
    ]

    /// To leave this state moving closer, RSSI must be **stronger** (less negative) than this.
    /// e.g. Close → Very Close when RSSI > -48.
    static let leaveCloser: [ProximityState: Double] = [
        .veryClose: -.greatestFiniteMagnitude,  // cannot leave closer
        .close:     -48,
        .nearby:    -58,
        .far:       -70,
        .veryFar:   -80,
        .offline:   -88,
    ]
}

// MARK: - Proximity Estimator

/// Computes a candidate proximity state from a smoothed RSSI value,
/// applying hysteresis relative to the current state to prevent boundary flicker.
enum ProximityEstimator {
    /// Determines the candidate proximity state given a median RSSI and the current visible state.
    ///
    /// Hysteresis logic: the RSSI must cross the "leave" threshold for the current state
    /// before transitioning. Once it crosses, the algorithm steps through adjacent states
    /// as long as the corresponding thresholds continue to be met.
    static func candidateState(medianRSSI rssi: Double, currentState: ProximityState) -> ProximityState {
        var candidate = currentState

        // Walk further away while thresholds allow it.
        while let next = candidate.nextFurther,
              rssi < HysteresisThreshold.leaveFurther[candidate, default: -.greatestFiniteMagnitude] {
            candidate = next
        }

        // Walk closer while thresholds allow it.
        while let next = candidate.nextCloser,
              rssi > HysteresisThreshold.leaveCloser[candidate, default: .greatestFiniteMagnitude] {
            candidate = next
        }

        return candidate
    }
}

// MARK: - Proximity Stabilizer

/// The main stabilisation engine that produces calm, debounced proximity states
/// from noisy RSSI readings.
///
/// ## Pipeline
/// 1. Raw RSSI → RSSIHistoryStore (ring buffer of last 7)
/// 2. History → median RSSI
/// 3. Median RSSI + current state → candidate state (via hysteresis)
/// 4. Candidate → persistence filter (3 consecutive for 1-step, 2 for 2+ steps)
/// 5. Debounce final output to at most 1 update per 2 seconds
///
/// ## Offline handling
/// - Last seen < 8 s ago: maintain current proximity state
/// - Last seen 8–30 s ago: transition to `.offline`
/// - Last seen > 30 s ago: remain `.offline`
final class ProximityStabilizer {
    // MARK: - Configuration

    /// Number of RSSI readings to keep in the rolling history.
    private let historyCapacity: Int

    /// Minimum seconds between visible state updates.
    private let minimumUpdateInterval: TimeInterval

    /// Seconds after last RSSI reading before entering offline state.
    private let offlineThreshold: TimeInterval

    // MARK: - State

    private var history = RSSIHistoryStore()
    private var currentState: ProximityState = .offline
    private var pendingCandidate: ProximityState?
    private var consecutiveCandidateCount = 0
    private var readyCandidate: ProximityState?
    private var lastVisibleUpdate: Date = .distantPast
    private var lastRSSIDate: Date?

    // MARK: - Initialization

    init(
        historyCapacity: Int = 7,
        minimumUpdateInterval: TimeInterval = 2,
        offlineThreshold: TimeInterval = 8
    ) {
        self.historyCapacity = historyCapacity
        self.minimumUpdateInterval = minimumUpdateInterval
        self.offlineThreshold = offlineThreshold
        self.history = RSSIHistoryStore(capacity: historyCapacity)
    }

    // MARK: - Public API

    /// Feed a new RSSI observation into the stabiliser.
    /// - Parameters:
    ///   - rssi: The raw RSSI value (dBm).
    ///   - date: The timestamp of the observation.
    func update(rssi: Int, at date: Date = Date()) {
        if let lastRSSIDate, date.timeIntervalSince(lastRSSIDate) > offlineThreshold {
            resetForOffline()
        }

        history.append(rssi)
        lastRSSIDate = date
        processCandidate(at: date)
    }

    /// Returns the current stabilised proximity state.
    /// - Parameter date: The current time, used for offline detection and update debouncing.
    /// - Returns: The stabilised `ProximityState`.
    func currentProximity(at date: Date = Date()) -> ProximityState {
        let elapsed = date.timeIntervalSince(lastRSSIDate ?? .distantPast)

        // Brief gaps should not disturb the visible proximity state.
        guard elapsed <= offlineThreshold else {
            resetForOffline()
            return .offline
        }

        if readyCandidate != nil {
            commitReadyCandidateIfAllowed(at: date)
        }

        return currentState
    }

    /// Reset all internal state.
    func reset() {
        history.clear()
        currentState = .offline
        pendingCandidate = nil
        readyCandidate = nil
        consecutiveCandidateCount = 0
        lastVisibleUpdate = .distantPast
        lastRSSIDate = nil
    }

    private func resetForOffline() {
        history.clear()
        currentState = .offline
        pendingCandidate = nil
        readyCandidate = nil
        consecutiveCandidateCount = 0
        lastVisibleUpdate = .distantPast
    }

    // MARK: - Candidate Processing

    private func processCandidate(at date: Date) {
        let elapsed = date.timeIntervalSince(lastRSSIDate ?? .distantPast)

        // Offline: no signal yet or signal too stale.
        if elapsed > offlineThreshold || lastRSSIDate == nil {
            return
        }

        guard let medianRSSI = history.median() else {
            return
        }

        let candidate = ProximityEstimator.candidateState(
            medianRSSI: medianRSSI,
            currentState: currentState
        )

        guard let persisted = applyPersistence(candidate: candidate) else {
            return
        }

        readyCandidate = persisted
        commitReadyCandidateIfAllowed(at: date)
    }

    private func commitReadyCandidateIfAllowed(at date: Date) {
        guard let readyCandidate else { return }
        guard date.timeIntervalSince(lastVisibleUpdate) >= minimumUpdateInterval else { return }

        currentState = readyCandidate
        lastVisibleUpdate = date
        self.readyCandidate = nil
    }

    // MARK: - Persistence Filter

    /// Requires consecutive candidate readings before a visible state change.
    ///
    /// - One-step changes (e.g. Close → Nearby): require 3 consecutive identical candidates.
    /// - Two-or-more-step changes (e.g. Close → Far): require 2 consecutive identical candidates.
    /// - If the candidate returns to the current visible state, the pending change is cancelled.
    ///
    /// - Returns: The new visible state if the persistence requirement is met, or `nil` to hold.
    private func applyPersistence(candidate: ProximityState) -> ProximityState? {
        if candidate == currentState {
            // Returned to visible state — cancel any pending transition.
            pendingCandidate = nil
            readyCandidate = nil
            consecutiveCandidateCount = 0
            return nil
        }

        if candidate == pendingCandidate {
            consecutiveCandidateCount += 1
        } else {
            pendingCandidate = candidate
            consecutiveCandidateCount = 1
        }

        let required = requiredPersistenceCount(
            from: currentState,
            to: candidate
        )

        guard consecutiveCandidateCount >= required else { return nil }

        // Persistence met — commit the change.
        pendingCandidate = nil
        consecutiveCandidateCount = 0
        return candidate
    }

    /// Returns the number of consecutive identical candidate readings required
    /// before a visible state transition is allowed.
    private func requiredPersistenceCount(from: ProximityState, to: ProximityState) -> Int {
        let allStates = ProximityState.allCases
        guard let fromIndex = allStates.firstIndex(of: from),
              let toIndex = allStates.firstIndex(of: to)
        else { return 3 }

        let steps = abs(allStates.distance(from: fromIndex, to: toIndex))
        return steps >= 2 ? 2 : 3
    }
}
