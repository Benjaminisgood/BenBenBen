import Foundation

enum MascotState: String, CaseIterable, Codable, Sendable {
    case idle
    case listening
    case thinking
    case working
    case waitingApproval
    case success
    case error
    case sleep

    var assetName: String {
        "ben-dragon-\(rawValue)"
    }

    var shortLabel: String {
        switch self {
        case .idle: return "Ben龙"
        case .listening: return "在听"
        case .thinking: return "想想"
        case .working: return "在做"
        case .waitingApproval: return "等你批准"
        case .success: return "好啦"
        case .error: return "卡住了"
        case .sleep: return "休息中"
        }
    }
}
