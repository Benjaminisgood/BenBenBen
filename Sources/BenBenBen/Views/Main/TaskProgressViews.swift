import SwiftUI

struct DragonTaskThoughtCloud: View {
    let threads: [AgentThread]
    @ObservedObject var store: AgentStore
    let selectedThreadID: String?
    let isDetailVisible: Bool
    let onSelect: (String) -> Void

    var body: some View {
        ZStack {
            ForEach(Array(orderedThreads.prefix(4).enumerated()), id: \.element.id) { index, thread in
                let isPrimary = index == 0
                Button {
                    onSelect(thread.id)
                } label: {
                    TaskThoughtBubble(
                        title: taskTitle(thread),
                        isPrimary: isPrimary,
                        phase: index
                    )
                }
                .buttonStyle(.plain)
                .position(position(for: index))
                .zIndex(Double(10 - index))
                .contextMenu {
                    ForEach(AgentTaskExecutionMode.allCases) { mode in
                        Button {
                            store.setExecutionMode(mode, for: thread.id)
                        } label: {
                            if store.executionMode(for: thread.id) == mode {
                                Label(mode.title, systemImage: "checkmark")
                            } else {
                                Text(mode.title)
                            }
                        }
                    }
                }
                .accessibilityLabel("正在思考：\(taskTitle(thread))")
                .accessibilityHint("点击切换到这个任务并查看进展")
            }

            if orderedThreads.count > 4 {
                Text("+\(orderedThreads.count - 4)")
                    .font(.caption2.bold())
                    .foregroundStyle(.cyan)
                    .padding(7)
                    .background(.ultraThinMaterial, in: .circle)
                    .position(x: 262, y: 154)
            }
        }
        .frame(width: 300, height: 178)
        .animation(.snappy(duration: 0.32), value: selectedThreadID)
        .animation(.snappy(duration: 0.32), value: threads.map(\.id))
    }

    private var orderedThreads: [AgentThread] {
        guard let selectedThreadID,
              let selected = threads.first(where: { $0.id == selectedThreadID }) else {
            return threads
        }
        return [selected] + threads.filter { $0.id != selectedThreadID }
    }

    private func position(for index: Int) -> CGPoint {
        if isDetailVisible {
            switch index {
            case 0: return CGPoint(x: 150, y: 42)
            case 1: return CGPoint(x: 238, y: 92)
            case 2: return CGPoint(x: 226, y: 139)
            default: return CGPoint(x: 70, y: 118)
            }
        }
        switch index {
        case 0: return CGPoint(x: 144, y: 40)
        case 1: return CGPoint(x: 244, y: 91)
        case 2: return CGPoint(x: 226, y: 142)
        default: return CGPoint(x: 63, y: 117)
        }
    }

    private func taskTitle(_ thread: AgentThread) -> String {
        let source = store.taskPrompts[thread.id] ?? thread.name ?? thread.preview
        let normalized = source.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return "任务 \(thread.id.prefix(6))" }
        let limit = 24
        return normalized.count > limit ? String(normalized.prefix(limit - 1)) + "…" : normalized
    }
}

private struct TaskThoughtBubble: View {
    let title: String
    let isPrimary: Bool
    let phase: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: isPrimary ? 8 : 6, height: isPrimary ? 8 : 6)
                    .shadow(color: .cyan.opacity(0.8), radius: 5)

                if isPrimary {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "ellipsis")
                        .font(.caption2.bold())
                        .foregroundStyle(.cyan)
                        .opacity(floating ? 1 : 0.45)
                } else {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                    Text(title)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, isPrimary ? 12 : 9)
            .padding(.vertical, isPrimary ? 9 : 7)
            .frame(maxWidth: isPrimary ? 190 : 118, alignment: .leading)
            .background(
                Color.cyan.opacity(isPrimary ? 0.16 : 0.10),
                in: .rect(cornerRadius: isPrimary ? 18 : 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: isPrimary ? 18 : 14)
                    .stroke(Color.cyan.opacity(isPrimary ? 0.52 : 0.28), lineWidth: 1)
            }

            Circle()
                .fill(Color.cyan.opacity(0.34))
                .frame(width: isPrimary ? 9 : 7, height: isPrimary ? 9 : 7)
                .offset(x: isPrimary ? 13 : 10, y: isPrimary ? 9 : 7)
            Circle()
                .fill(Color.cyan.opacity(0.22))
                .frame(width: isPrimary ? 5 : 4, height: isPrimary ? 5 : 4)
                .offset(x: isPrimary ? 7 : 5, y: isPrimary ? 17 : 13)
        }
        .offset(y: reduceMotion ? 0 : (floating ? -4 : 3))
        .scaleEffect(reduceMotion ? 1 : (floating ? 1.015 : 0.985))
        .shadow(color: .cyan.opacity(isPrimary ? 0.18 : 0.08), radius: isPrimary ? 12 : 7)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 1.45 + Double(phase) * 0.17)
                    .delay(Double(phase) * 0.12)
                    .repeatForever(autoreverses: true)
            ) {
                floating = true
            }
        }
    }
}

struct TaskProgressDetailCard: View {
    let threadID: String
    @ObservedObject var store: AgentStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(status.companionStatusColor).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(status.companionStatusLabel).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }

            HStack {
                Text("权限")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Picker("权限", selection: executionModeBinding) {
                    ForEach(AgentTaskExecutionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Spacer()
                if let usage = store.tokenUsage[threadID] {
                    Text("\(usage.total.totalTokens) tokens")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !plan.isEmpty {
                        Text("计划").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(plan) { step in
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: step.status.companionPlanIcon)
                                    .foregroundStyle(step.status.companionStatusColor)
                                Text(step.step).font(.caption).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if !activities.isEmpty {
                        Text("实时进展").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(activities) { activity in
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: activity.kind.companionSystemImage)
                                    .foregroundStyle(activity.status.companionStatusColor)
                                    .frame(width: 13)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(activity.title).font(.caption.weight(.medium))
                                    if let detail = activity.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(activity.kind == .command ? .caption2.monospaced() : .caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }

                    if !liveReply.isEmpty {
                        Text("Ben龙 回复").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(liveReply)
                            .font(.caption)
                            .lineLimit(6)
                            .textSelection(.enabled)
                    } else if let output = recentOutput, !output.isEmpty {
                        Text("最新输出").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(output)
                            .font(.caption2.monospaced())
                            .lineLimit(5)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 210)

            if let turn = store.activeTurns[threadID], turn.status.isCompanionRunning {
                HStack {
                    Text("下方输入会直接引导这个任务")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("停止", systemImage: "stop.fill", role: .destructive) {
                        Task { await store.interrupt(threadID: threadID, turnID: turn.id) }
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private var thread: AgentThread? { store.threads.first { $0.id == threadID } }
    private var title: String {
        store.taskPrompts[threadID] ?? thread?.name ?? thread?.preview ?? "任务 \(threadID.prefix(6))"
    }
    private var status: String { store.activeTurns[threadID]?.status ?? thread?.status ?? "idle" }
    private var plan: [AgentPlanStep] { store.taskPlans[threadID] ?? [] }
    private var activities: [AgentTaskActivity] { Array((store.taskActivities[threadID] ?? []).suffix(6)) }
    private var liveReply: String {
        store.agentMessages[threadID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    private var recentOutput: String? {
        store.commandOutputsByThread[threadID]?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var executionModeBinding: Binding<AgentTaskExecutionMode> {
        Binding(
            get: { store.executionMode(for: threadID) },
            set: { store.setExecutionMode($0, for: threadID) }
        )
    }
}

extension AgentTaskActivityKind {
    var companionSystemImage: String {
        switch self {
        case .lifecycle: return "sparkles"
        case .command: return "terminal"
        case .fileChange: return "doc.badge.gearshape"
        case .tool: return "wrench.and.screwdriver"
        case .reasoning: return "brain"
        case .message: return "text.bubble"
        case .approval: return "hand.raised"
        case .guidance: return "arrow.turn.down.right"
        }
    }
}

extension String {
    var isCompanionRunning: Bool {
        let value = lowercased()
        return value.contains("progress") || value == "running" || value == "started"
    }

    var companionStatusColor: Color {
        let value = lowercased()
        if value.contains("progress") || value == "running" || value == "started" { return .cyan }
        if value == "completed" || value == "success" { return .green }
        if value == "failed" || value == "error" { return .red }
        if value == "waiting" || value == "pending" { return .orange }
        if value == "interrupted" || value == "cancelled" { return .secondary }
        return .secondary
    }

    var companionStatusLabel: String {
        let value = lowercased()
        if value.contains("progress") || value == "running" || value == "started" {
            return "正在执行，可随时继续引导"
        }
        if value == "completed" || value == "success" { return "已完成" }
        if value == "failed" || value == "error" { return "执行失败" }
        if value == "interrupted" || value == "cancelled" { return "已停止" }
        return "等待中"
    }

    var companionPlanIcon: String {
        let value = lowercased()
        if value == "completed" { return "checkmark.circle.fill" }
        if value.contains("progress") { return "circle.dotted.circle.fill" }
        return "circle"
    }
}
