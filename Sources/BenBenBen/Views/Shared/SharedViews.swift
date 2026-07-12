import AppKit
import MarkdownEngine
import MarkdownEngineLatex
import SwiftUI

let leftPickerPopoverAnchor = UnitPoint(x: 1, y: 0.5)

struct TopToolbarButtonStrip<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 3) {
            content
        }
        .padding(.horizontal, 3)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.035))
        )
    }
}

struct ToolbarSearchField<Results: View>: View {
    let placeholder: String
    @Binding var query: String
    let resultCount: Int
    @Binding var isShowingResults: Bool
    @ViewBuilder let results: () -> Results

    @FocusState private var isFocused: Bool

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 16, height: 22)

            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
                .focused($isFocused)
                .onChange(of: query) { _, nextQuery in
                    isShowingResults = !nextQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }

            if hasQuery {
                Text("\(resultCount)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(minWidth: 22, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 188, height: 28, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(isFocused ? 0.065 : 0.045))
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .popover(isPresented: $isShowingResults, arrowEdge: .bottom) {
            results()
        }
    }
}

enum ScriptToolbarMode {
    case run
    case ai
}

struct ScriptToolbarModeButton: View {
    @Binding var mode: ScriptToolbarMode

    var body: some View {
        Button {
            mode = mode == .run ? .ai : .run
        } label: {
            Image(systemName: mode == .run ? "sparkles" : "terminal")
                .frame(width: 26, height: 24)
        }
        .buttonStyle(MarkdownToolbarButtonStyle())
        .help(mode == .run ? "Switch to AI edit" : "Switch to command finder")
    }
}

struct OpenCurrentFileInVSCodeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .frame(width: 26, height: 24)
        }
        .buttonStyle(MarkdownToolbarButtonStyle())
        .help("Open this file in VS Code")
    }
}

struct ScriptAIReviewView: View {
    @ObservedObject var aiStore: ScriptAIEditStore

    var body: some View {
        ScrollView {
            Text(reviewText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .textSelection(.enabled)
        }
        .background(Color(red: 0.045, green: 0.047, blue: 0.055))
    }

    private var reviewText: String {
        if let proposal = aiStore.proposal {
            return "\(aiStore.statusText)\n\n\(proposal.replacementScript)"
        }
        return aiStore.statusText
    }
}

struct ScriptAIEditorControls: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var aiStore: ScriptAIEditStore
    let language: ScriptLanguage
    let fileName: String
    let script: String
    let onApply: (String) -> Void
    let isReadOnly: Bool

    var body: some View {
        TextField("Describe script edit", text: $aiStore.input)
            .textFieldStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.84))
            .disabled(aiStore.isRunning || isReadOnly)
            .onSubmit(submit)

        Button(action: submit) {
            Image(systemName: "sparkles")
                .frame(width: 26, height: 24)
        }
        .buttonStyle(MarkdownToolbarButtonStyle())
        .disabled(!aiStore.canSubmit || isReadOnly)
        .help("Generate \(language.rawValue) proposal")

        if let proposal = aiStore.proposal {
            Button {
                aiStore.rejectProposal()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .help("Reject proposal")

            Button {
                onApply(proposal.replacementScript)
                aiStore.acceptProposal()
            } label: {
                Image(systemName: "checkmark")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(isReadOnly)
            .help("Apply proposal")
        }
    }

    private func submit() {
        guard !isReadOnly else { return }
        aiStore.submit(
            settings: settingsStore,
            language: language,
            fileName: fileName,
            script: script
        )
    }
}

struct CodeSearchResultsPopover: View {
    let files: [CodeFile]
    let activeFileID: UUID
    let onSelect: (CodeFile) -> Void

    var body: some View {
        SearchResultsContainer {
            if files.isEmpty {
                EmptySearchResultView()
            } else {
                ForEach(files) { file in
                    Button {
                        onSelect(file)
                    } label: {
                        SearchResultRow(
                            systemImage: file.id == activeFileID ? "curlybraces.square.fill" : "curlybraces.square",
                            title: file.fileName,
                            detail: file.filePath
                        )
                    }
                    .buttonStyle(FilePillButtonStyle(isSelected: file.id == activeFileID))
                    .help(file.fileName)
                }
            }
        }
    }
}

struct ActiveFileBadge: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))
                .frame(width: 14)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)

            if !detail.isEmpty, detail != title {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.36))
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 0, maxWidth: 260, alignment: .leading)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.035))
        )
        .help(detail)
    }
}

struct FilePermissionLockButton: View {
    @ObservedObject var lockStore: FilePermissionLockStore
    let fileURL: URL?

    private var isLocked: Bool {
        lockStore.isLocked(fileURL)
    }

    var body: some View {
        Button {
            lockStore.toggle(fileURL)
        } label: {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .frame(width: 24, height: 22)
        }
        .buttonStyle(MarkdownToolbarButtonStyle())
        .disabled(fileURL == nil)
        .help(helpText)
    }

    private var helpText: String {
        if let error = lockStore.lastError {
            return error
        }
        return isLocked
            ? "Unlock file for writing"
            : "Lock file as read-only"
    }
}

struct StoreErrorBadge: View {
    let message: String

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.orange.opacity(0.9))
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.orange.opacity(0.10))
            )
            .help(message)
    }
}

struct SearchResultsContainer<Content: View>: View {
    let content: Content
    let width: CGFloat
    let height: CGFloat

    init(width: CGFloat = 260, height: CGFloat = 260, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.width = width
        self.height = height
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                content
            }
            .padding(6)
        }
        .frame(width: width, height: height)
        .background(Color(red: 0.04, green: 0.042, blue: 0.05))
    }
}

struct SearchResultRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)

                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "return")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(minHeight: 34)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }
}

struct EmptySearchResultView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.42))
                .frame(width: 16)

            Text("No results")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))

            Spacer(minLength: 0)
        }
        .frame(height: 34)
        .padding(.horizontal, 10)
    }
}

struct OutputView: View {
    let output: String
    private let bottomID = "output-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(output.isEmpty ? " " : output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.76))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(10)
            }
            .background(Color(red: 0.035, green: 0.037, blue: 0.044))
            .onAppear {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
            .onChange(of: output) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
        }
    }
}

struct CompactNotchView: View {
    let layout: NotchLayout
    @ObservedObject var mascotModel: MascotModel
    @ObservedObject var voiceInteraction: VoiceInteractionController

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            MascotView(
                state: mascotModel.presentedState,
                size: 44,
                revision: mascotModel.presentationRevision
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(mascotModel.state.shortLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.90))
                Text(statusText)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .padding(.bottom, 7)

            Spacer(minLength: 0)

            if let seconds = voiceInteraction.countdownSeconds {
                Text("\(seconds)")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.bottom, 8)
            } else if mascotModel.state == .waitingApproval {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                    .padding(.bottom, 9)
            }
        }
            .padding(.horizontal, 10)
            .padding(.bottom, 5)
            .frame(
                width: layout.compactSize.width,
                height: layout.compactSize.height,
                alignment: .bottom
            )
            .background(Color(red: 0.02, green: 0.02, blue: 0.025).opacity(0.98))
            .clipShape(TopAttachedRoundedShape(radius: 12))
            .overlay(
                TopAttachedRoundedShape(radius: 12)
                    .stroke(.white.opacity(0.09), lineWidth: 1)
            )
            .pointingHandCursor()
    }

    private var statusText: String {
        if voiceInteraction.isRecording {
            if !voiceInteraction.liveTranscript.isEmpty {
                return voiceInteraction.liveTranscript
            }
            return voiceInteraction.isConversationEnabled ? "持续聆听中" : "按住说话，松开发送"
        }
        if let pending = voiceInteraction.pendingTranscript {
            return "点击取消：\(pending)"
        }
        return mascotModel.bubbleText
            ?? (voiceInteraction.isConversationEnabled ? "单击展开 · 语音常驻" : "单击展开 · 按住说话")
    }
}

struct TopAttachedRoundedShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}

struct DarkIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 13, weight: .semibold),
            normalOpacity: 0.055,
            hoverOpacity: 0.085,
            pressedOpacity: 0.12,
            strokeOpacity: 0.06,
            foregroundOpacity: 0.76,
            pressedForegroundOpacity: 0.55
        )
    }
}

struct TabIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 11, weight: .bold),
            normalOpacity: 0,
            hoverOpacity: 0.065,
            pressedOpacity: 0.10,
            strokeOpacity: 0,
            foregroundOpacity: 0.72,
            pressedForegroundOpacity: 0.48
        )
    }
}

struct TabDotButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 11, weight: .semibold),
            normalOpacity: isSelected ? 0.045 : 0,
            hoverOpacity: isSelected ? 0.075 : 0.055,
            pressedOpacity: isSelected ? 0.10 : 0.08,
            strokeOpacity: 0,
            foregroundOpacity: 0.72,
            pressedForegroundOpacity: 0.58
        )
    }
}

struct MarkdownToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 11, weight: .semibold),
            normalOpacity: 0,
            hoverOpacity: 0.065,
            pressedOpacity: 0.10,
            strokeOpacity: 0,
            foregroundOpacity: 0.66,
            hoverForegroundOpacity: 0.84,
            pressedForegroundOpacity: 0.54
        )
    }
}

struct WorkbenchModeButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: nil,
            normalOpacity: isSelected ? 0.14 : 0,
            hoverOpacity: isSelected ? 0.18 : 0.07,
            pressedOpacity: 0.22,
            strokeOpacity: isSelected ? 0.10 : 0,
            foregroundOpacity: isSelected ? 0.92 : 0.58,
            hoverForegroundOpacity: 0.9,
            pressedForegroundOpacity: 0.72
        )
    }
}

struct FilePillButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: nil,
            normalOpacity: isSelected ? 0.12 : 0.045,
            hoverOpacity: isSelected ? 0.16 : 0.08,
            pressedOpacity: 0.18,
            strokeOpacity: isSelected ? 0.10 : 0.04,
            foregroundOpacity: isSelected ? 0.9 : 0.68,
            hoverForegroundOpacity: 0.9,
            pressedForegroundOpacity: 0.68
        )
    }
}

private struct RoundedHoverButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let font: Font?
    let normalOpacity: CGFloat
    let hoverOpacity: CGFloat
    let pressedOpacity: CGFloat
    let strokeOpacity: CGFloat
    let foregroundOpacity: CGFloat
    let hoverForegroundOpacity: CGFloat
    let pressedForegroundOpacity: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    init(
        configuration: ButtonStyle.Configuration,
        font: Font?,
        normalOpacity: CGFloat,
        hoverOpacity: CGFloat,
        pressedOpacity: CGFloat,
        strokeOpacity: CGFloat,
        foregroundOpacity: CGFloat,
        hoverForegroundOpacity: CGFloat? = nil,
        pressedForegroundOpacity: CGFloat
    ) {
        self.configuration = configuration
        self.font = font
        self.normalOpacity = normalOpacity
        self.hoverOpacity = hoverOpacity
        self.pressedOpacity = pressedOpacity
        self.strokeOpacity = strokeOpacity
        self.foregroundOpacity = foregroundOpacity
        self.hoverForegroundOpacity = hoverForegroundOpacity ?? foregroundOpacity
        self.pressedForegroundOpacity = pressedForegroundOpacity
    }

    var body: some View {
        configuration.label
            .font(font)
            .foregroundStyle(.white.opacity(currentForegroundOpacity))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(currentBackgroundOpacity))
            )
            .animation(.easeOut(duration: 0.10), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hovering in
                guard isEnabled else { return }
                isHovering = hovering
            }
            .pointingHandCursor(isEnabled: isEnabled)
    }

    private var currentBackgroundOpacity: CGFloat {
        guard isEnabled else { return 0 }
        if configuration.isPressed {
            return pressedOpacity
        }
        return isHovering ? hoverOpacity : normalOpacity
    }

    private var currentForegroundOpacity: CGFloat {
        guard isEnabled else { return 0.22 }
        if configuration.isPressed {
            return pressedForegroundOpacity
        }
        return isHovering ? hoverForegroundOpacity : foregroundOpacity
    }
}

private extension View {
    func pointingHandCursor(isEnabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(isEnabled: isEnabled))
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    let isEnabled: Bool
    @State private var isCursorActive = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering, isEnabled, !isCursorActive {
                    NSCursor.pointingHand.push()
                    isCursorActive = true
                } else if (!hovering || !isEnabled), isCursorActive {
                    NSCursor.pop()
                    isCursorActive = false
                }
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled, isCursorActive {
                    NSCursor.pop()
                    isCursorActive = false
                }
            }
            .onDisappear {
                if isCursorActive {
                    NSCursor.pop()
                    isCursorActive = false
                }
            }
    }
}
