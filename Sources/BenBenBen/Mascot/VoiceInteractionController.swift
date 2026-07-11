@preconcurrency import AVFoundation
import Combine
import Foundation
@preconcurrency import Speech

@MainActor
final class VoiceInteractionController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var liveTranscript = ""
    @Published private(set) var pendingTranscript: String?
    @Published private(set) var countdownSeconds: Int?
    @Published private(set) var lastError: String?
    @Published var speaksVoiceReplies = UserDefaults.standard.object(forKey: "benbenben.voiceReplies") as? Bool ?? true {
        didSet { UserDefaults.standard.set(speaksVoiceReplies, forKey: "benbenben.voiceReplies") }
    }

    var onSend: ((String) -> Void)?
    var onStateChanged: ((Bool) -> Void)?
    var onCountdownChanged: ((String, Int) -> Void)?
    var onError: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var countdownTask: Task<Void, Never>?
    private var inputTapInstalled = false

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    func startRecording() async {
        guard !isRecording else { return }
        cancelPending()

        guard await ensurePermissions() else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            fail("当前语言的系统语音识别暂不可用")
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        liveTranscript = ""
        lastError = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.liveTranscript = result.bestTranscription.formattedString
                }
                if let error, self.isRecording {
                    self.finishAudioCapture()
                    self.fail(error.localizedDescription)
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("没有可用的麦克风输入")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        inputTapInstalled = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            onStateChanged?(true)
        } catch {
            finishAudioCapture()
            fail("无法开始录音：\(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        finishAudioCapture()
        onStateChanged?(false)

        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            fail("没有听清，再按住 Ben龙 说一次吧")
            return
        }
        beginSendCountdown(with: text)
    }

    func cancelPending() {
        countdownTask?.cancel()
        countdownTask = nil
        pendingTranscript = nil
        countdownSeconds = nil
    }

    func interruptSpeech() {
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    func speakVoiceInitiatedReply(_ text: String) {
        guard speaksVoiceReplies else { return }
        let summary = Self.shortSpokenSummary(text)
        guard !summary.isEmpty else { return }
        interruptSpeech()
        let utterance = AVSpeechUtterance(string: summary)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier)
        utterance.rate = 0.48
        speechSynthesizer.speak(utterance)
    }

    private func beginSendCountdown(with text: String) {
        pendingTranscript = text
        countdownSeconds = 2
        onCountdownChanged?(text, 2)
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            for seconds in stride(from: 2, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.countdownSeconds = seconds
                self.onCountdownChanged?(text, seconds)
                try? await Task.sleep(for: .seconds(1))
            }
            guard let self, !Task.isCancelled, self.pendingTranscript == text else { return }
            self.pendingTranscript = nil
            self.countdownSeconds = nil
            self.onSend?(text)
        }
    }

    private func finishAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if inputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        isRecording = false
    }

    private func ensurePermissions() async -> Bool {
        let speechAuthorized: Bool
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechAuthorized = true
        case .notDetermined:
            speechAuthorized = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            speechAuthorized = false
        }
        guard speechAuthorized else {
            fail("请在系统设置中允许 BenBenBen 使用语音识别")
            return false
        }

        let microphoneAuthorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneAuthorized = true
        case .notDetermined:
            microphoneAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            microphoneAuthorized = false
        }
        guard microphoneAuthorized else {
            fail("请在系统设置中允许 BenBenBen 使用麦克风")
            return false
        }
        return true
    }

    private func fail(_ message: String) {
        lastError = message
        onError?(message)
    }

    private static func shortSpokenSummary(_ raw: String) -> String {
        let text = raw
            .replacingOccurrences(of: #"```[\s\S]*?```"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[`#>*_\[\]]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 320 else { return text }

        let sentences = text.split(whereSeparator: { ".。！？!?".contains($0) })
        let summary = sentences.prefix(2).joined(separator: "。")
        return String(summary.prefix(260))
    }
}
