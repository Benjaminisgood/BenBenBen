import SwiftUI

struct TaskBubbleLabel: View {
    let title: String
    let status: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(status.companionStatusColor)
                .frame(width: 7, height: 7)
                .shadow(color: status.companionStatusColor.opacity(0.7), radius: status.isCompanionRunning ? 4 : 0)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if status.isCompanionRunning {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            isSelected ? Color.cyan.opacity(0.18) : Color.white.opacity(0.075),
            in: .rect(cornerRadius: 15)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(isSelected ? Color.cyan.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
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
