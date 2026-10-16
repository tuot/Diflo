import SwiftUI

struct DifferenceNavigationView: View {
    let session: ComparisonSession

    var body: some View {
        HStack(spacing: 0) {
            Button(action: session.selectPreviousHunk) {
                Label("上一个差异", systemImage: "chevron.up")
                    .frame(width: 20, height: 28)
                    .contentShape(.rect)
            }
                .help("上一个差异 (⌘↑)")
                .keyboardShortcut(.upArrow, modifiers: [.command])
                .disabled(!canNavigate)

            Group {
                if session.isWorking {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Text(summary)
                        .font(.system(size: 11).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)

            Button(action: session.selectNextHunk) {
                Label("下一个差异", systemImage: "chevron.down")
                    .frame(width: 20, height: 28)
                    .contentShape(.rect)
            }
                .help("下一个差异 (⌘↓)")
                .keyboardShortcut(.downArrow, modifiers: [.command])
                .disabled(!canNavigate)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .controlSize(.small)
        .padding(.horizontal, 2)
        .frame(width: ChangeGutterView.preferredWidth - 8, height: 28)
        .accessibilityIdentifier("差异导航")
    }

    private var canNavigate: Bool {
        !session.isWorking && session.result?.hunks.isEmpty == false
    }

    private var selectedIndex: Int? {
        session.result?.hunks.firstIndex { $0.id == session.selectedHunkID }
    }

    private var summary: String {
        guard !session.isWorking, let result = session.result else { return "正在比较" }
        guard !result.hunks.isEmpty else { return "相同" }
        guard let selectedIndex else { return "–/\(result.hunks.count)" }
        return "\(selectedIndex + 1)/\(result.hunks.count)"
    }

    private var accessibilitySummary: String {
        guard !session.isWorking, let result = session.result else { return "正在比较" }
        guard !result.hunks.isEmpty else { return "内容相同" }
        guard let selectedIndex else { return "共 \(result.hunks.count) 处差异，尚未选择" }
        return "第 \(selectedIndex + 1) 处差异，共 \(result.hunks.count) 处"
    }
}
