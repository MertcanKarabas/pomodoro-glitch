import Foundation

public enum Phase: String, Codable, Sendable, CaseIterable {
    case work
    case shortBreak
    case longBreak

    public var isBreak: Bool { self != .work }

    public var title: String {
        switch self {
        case .work: "Work"
        case .shortBreak: "Break"
        case .longBreak: "Long break"
        }
    }
}
