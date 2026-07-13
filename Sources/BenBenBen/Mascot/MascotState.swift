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
    case cameraReady
    case cameraShutter
    case walkLeft
    case walkRight
    case teaHold
    case teaSip
    case daydream
    case cloudWatch
    case rest
    case read
    case music
    case waterFlower
    case snack
    case stretch
    case sketch
    case rain
    case stargaze
    case bubbles

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
        case .cameraReady, .cameraShutter: return "拍张照片"
        case .walkLeft, .walkRight: return "散散步"
        case .teaHold, .teaSip: return "喝口茶"
        case .daydream: return "发会儿呆"
        case .cloudWatch: return "看看云"
        case .rest: return "歇一会儿"
        case .read: return "看会儿书"
        case .music: return "听听歌"
        case .waterFlower: return "浇浇花"
        case .snack: return "吃点心"
        case .stretch: return "伸懒腰"
        case .sketch: return "画点什么"
        case .rain: return "听听雨"
        case .stargaze: return "看看星星"
        case .bubbles: return "吹泡泡"
        }
    }

    var isAmbientOnly: Bool {
        switch self {
        case .cameraReady, .cameraShutter, .walkLeft, .walkRight,
             .teaHold, .teaSip, .daydream, .cloudWatch, .rest, .read,
             .music, .waterFlower, .snack, .stretch, .sketch, .rain,
             .stargaze, .bubbles:
            return true
        default:
            return false
        }
    }
}
