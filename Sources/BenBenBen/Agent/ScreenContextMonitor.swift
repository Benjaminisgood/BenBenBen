import AppKit
import Combine
import CoreGraphics
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
final class ScreenContextMonitor: ObservableObject {
    enum Status: Equatable {
        case off
        case requestingPermission
        case observing
        case denied
        case failed(String)

        var label: String {
            switch self {
            case .off: return "屏幕未共享"
            case .requestingPermission: return "等待屏幕权限"
            case .observing: return "屏幕上下文已开启"
            case .denied: return "屏幕权限未授权"
            case .failed(let message): return message
            }
        }
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var latestScreenshotURL: URL?
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            isEnabled ? start() : stop()
        }
    }

    private static let enabledKey = "benbenben.screenContext.enabled"
    private var captureTask: Task<Void, Never>?
    private var previousSignature: [UInt8]?
    private var lastReactionDate = Date.distantPast
    var onSignificantChange: ((URL) -> Void)?

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    func start() {
        guard captureTask == nil else { return }
        status = .requestingPermission
        captureTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.isEnabled {
                _ = await self.captureLatest(notifyOnChange: true)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stop() {
        captureTask?.cancel()
        captureTask = nil
        status = .off
    }

    func captureLatest(notifyOnChange: Bool = false) async -> URL? {
        guard isEnabled else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let targetID = NotchGeometry.targetScreen()?.displayID,
                  let display = content.displays.first(where: { $0.displayID == targetID })
                    ?? content.displays.first else {
                status = .failed("找不到可共享的屏幕")
                return nil
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            let scale = min(1, 1600 / CGFloat(max(display.width, 1)))
            configuration.width = max(1, Int(CGFloat(display.width) * scale))
            configuration.height = max(1, Int(CGFloat(display.height) * scale))
            configuration.showsCursor = true
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            let url = try write(image)
            latestScreenshotURL = url
            status = .observing
            if notifyOnChange {
                detectSignificantChange(in: image, url: url)
            }
            return url
        } catch {
            let nsError = error as NSError
            status = nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
                ? .denied
                : .failed(error.localizedDescription)
            return nil
        }
    }

    private func write(_ image: CGImage) throws -> URL {
        let directory = WorkspacePaths.root
            .appendingPathComponent(".benbenben/screen", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("latest.png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    private func detectSignificantChange(in image: CGImage, url: URL) {
        let width = 20
        let height = 12
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        defer { previousSignature = pixels }
        guard let previousSignature, previousSignature.count == pixels.count else { return }
        let averageDelta = zip(previousSignature, pixels).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        } / pixels.count
        guard averageDelta >= 14,
              Date().timeIntervalSince(lastReactionDate) >= 15 else { return }
        lastReactionDate = Date()
        onSignificantChange?(url)
    }
}
