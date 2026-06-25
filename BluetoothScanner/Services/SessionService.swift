import Foundation

struct SessionService {
    private(set) var sessions: [ScanSession] = []
    private var currentSession: ScanSession?
    private let rollingWindow: TimeInterval

    init(rollingWindow: TimeInterval = 30) {
        self.rollingWindow = rollingWindow
    }

    mutating func restore(sessions: [ScanSession]) {
        self.sessions = sessions
        currentSession = nil
    }

    mutating func startSession(at date: Date = Date()) {
        currentSession = ScanSession(id: UUID(), startedAt: date, endedAt: nil, deviceIds: [])
    }

    mutating func record(deviceId: String, at date: Date = Date()) {
        if currentSession == nil {
            startSession(at: date)
        }

        if let startedAt = currentSession?.startedAt, date.timeIntervalSince(startedAt) > rollingWindow {
            _ = endCurrentSession(at: date)
            startSession(at: date)
        }

        currentSession?.deviceIds.insert(deviceId)
    }

    mutating func endCurrentSession(at date: Date = Date()) -> [ScanSession] {
        guard var session = currentSession else { return sessions }
        session.endedAt = date

        if !session.deviceIds.isEmpty {
            sessions.append(session)
        }

        currentSession = nil
        return sessions
    }
}
