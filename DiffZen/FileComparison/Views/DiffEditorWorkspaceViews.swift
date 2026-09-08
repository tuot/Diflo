import SwiftUI

// MARK: - Meld 官方配色规范体系 (提炼自 meld-base 与 meld-dark)

enum MeldTheme {
    static func insertBackground(isDark: Bool) -> Color {
        isDark ? Color(red: 0x12 / 255.0, green: 0x38 / 255.0, blue: 0x06 / 255.0)
               : Color(red: 0xd0 / 255.0, green: 0xff / 255.0, blue: 0xa3 / 255.0).opacity(0.85)
    }

    static func insertBorder(isDark: Bool) -> Color {
        isDark ? Color(red: 0x24 / 255.0, green: 0x55 / 255.0, blue: 0x15 / 255.0)
               : Color(red: 0xa5 / 255.0, green: 0xff / 255.0, blue: 0x4c / 255.0)
    }

    static func replaceBackground(isDark: Bool) -> Color {
        isDark ? Color(red: 0x00 / 255.0, green: 0x32 / 255.0, blue: 0x66 / 255.0)
               : Color(red: 0xbd / 255.0, green: 0xdd / 255.0, blue: 0xff / 255.0).opacity(0.85)
    }

    static func replaceBorder(isDark: Bool) -> Color {
        isDark ? Color(red: 0x00 / 255.0, green: 0x53 / 255.0, blue: 0xa6 / 255.0)
               : Color(red: 0x65 / 255.0, green: 0xb2 / 255.0, blue: 0xff / 255.0)
    }

    static func inlineDiffBackground(isDark: Bool) -> Color {
        isDark ? Color(red: 0x24 / 255.0, green: 0x52 / 255.0, blue: 0x7e / 255.0)
               : Color(red: 0x8a / 255.0, green: 0xc2 / 255.0, blue: 0xff / 255.0)
    }

    static func deleteBackground(isDark: Bool) -> Color {
        isDark ? Color(red: 0x7a / 255.0, green: 0x2a / 255.0, blue: 0x28 / 255.0)
               : Color(red: 0xff / 255.0, green: 0xa5 / 255.0, blue: 0xa3 / 255.0).opacity(0.85)
    }

    static func deleteBorder(isDark: Bool) -> Color {
        isDark ? Color(red: 0xac / 255.0, green: 0x3b / 255.0, blue: 0x39 / 255.0)
               : Color(red: 0xff / 255.0, green: 0x4f / 255.0, blue: 0x4c / 255.0)
    }
}

// MARK: - Meld 原生双栏工作区 (宽高严格以 App 为准，内容超出内部滚动，左右严格 1:1 平分)

struct MeldDualEditorWorkspaceView: View {
    let session: ComparisonSession

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    private let rowHeight: CGFloat = 20.0
    private let topPadding: CGFloat = 6.0
    private let charWidth: CGFloat = 7.82

    var body: some View {
        GeometryReader { geometry in
            let viewportHeight = geometry.size.height
            let maxLineCount = max(session.leftBuffer.lineCount, session.rightBuffer.lineCount, 1)
            let neededHeight = topPadding * 2 + CGFloat(maxLineCount) * rowHeight + 80
            let contentHeight = max(viewportHeight, neededHeight)

            HStack(spacing: 0) {
                // 1. 核心滚动工作区：左右双栏与中央连线统一协同滚动 (绝不改变外框尺寸)
                ScrollView(.vertical) {
                    HStack(spacing: 0) {
                        // 左侧编辑区域 (严格平分 50% 宽度)
                        editorPane(side: .left, contentHeight: contentHeight)
                            .frame(maxWidth: .infinity)

                        Divider()

                        // 中央 Gutter 连线带 (与代码绝对同频滚动)
                        centralGutter(contentHeight: contentHeight)
                            .frame(width: 58)

                        Divider()

                        // 右侧编辑区域 (严格平分 50% 宽度)
                        editorPane(side: .right, contentHeight: contentHeight)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(minHeight: viewportHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                Divider()

                // 2. 右侧常驻小地图 (Overview)
                SwiftUIOverviewView(
                    hunks: session.result?.hunks ?? [],
                    totalLines: maxLineCount
                )
                .frame(width: 14)
                .frame(maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
    }

    // MARK: - 单侧编辑器面板 (标尺 + 代码区)

    @ViewBuilder
    private func editorPane(side: ComparisonSide, contentHeight: CGFloat) -> some View {
        let buffer = side == .left ? session.leftBuffer : session.rightBuffer
        let oppositeBuffer = side == .left ? session.rightBuffer : session.leftBuffer
        let lineCount = max(buffer.lineCount, 1)

        HStack(spacing: 0) {
            // 1. 标尺行号列 (严格与文本每行基线对齐)
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(0..<lineCount, id: \.self) { lineIndex in
                    HStack(spacing: 3) {
                        if let marker = marker(for: side, lineIndex: lineIndex) {
                            Text(marker)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(markerColor(for: side, lineIndex: lineIndex))
                        } else {
                            Spacer().frame(width: 8)
                        }

                        Text("\(lineIndex + 1)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .frame(height: rowHeight)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background(rowBackgroundColor(for: side, lineIndex: lineIndex))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, topPadding)
            .frame(width: 44)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))

            Divider()

            // 2. 真实多行文本编辑核心区 (支持行内字符差异高亮)
            ZStack(alignment: .topLeading) {
                Color(nsColor: .textBackgroundColor)

                // 差异背景色块层与字符级高亮层
                VStack(spacing: 0) {
                    ForEach(0..<lineCount, id: \.self) { lineIndex in
                        ZStack(alignment: .leading) {
                            // 整行背景色
                            Rectangle()
                                .fill(rowBackgroundColor(for: side, lineIndex: lineIndex))
                                .frame(height: rowHeight)

                            // 行内字符高亮 (严格以行首为基准，绝不居中漂浮)
                            if diffKind(for: side, lineIndex: lineIndex) == .modified {
                                let currentLine = lineIndex < buffer.lines.count ? buffer.lines[lineIndex] : ""
                                let oppLine = lineIndex < oppositeBuffer.lines.count ? oppositeBuffer.lines[lineIndex] : ""
                                let (leftRanges, rightRanges) = IntraLineDiffEngine.diff(left: side == .left ? currentLine : oppLine, right: side == .left ? oppLine : currentLine)
                                let ranges = side == .left ? leftRanges : rightRanges

                                ForEach(0..<ranges.count, id: \.self) { idx in
                                    let range = ranges[idx]
                                    let startX = 11.0 + CGFloat(range.location) * charWidth
                                    let width = CGFloat(range.length) * charWidth

                                    HStack(spacing: 0) {
                                        Spacer().frame(width: startX)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(MeldTheme.inlineDiffBackground(isDark: isDark))
                                            .frame(width: max(width, 6), height: rowHeight - 3)
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }
                        .frame(height: rowHeight)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, topPadding)
                .allowsHitTesting(false)

                // 真实文本编辑框 (TextEditor，高度跟随内容延伸，统一由外部平滑滚动)
                TextEditor(text: Binding(
                    get: { buffer.text },
                    set: { session.edit(side, text: $0) }
                ))
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .padding(.horizontal, 6)
                .padding(.top, topPadding)
                .frame(minHeight: contentHeight)

                // 空白占位文字
                if buffer.text.isEmpty {
                    Text(side == .left ? "输入或粘贴左侧文本..." : "输入或粘贴右侧文本...")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 11)
                        .padding(.top, topPadding + 2)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(minHeight: contentHeight)
    }

    // MARK: - 中央 Gutter 连线带 (Cubic Bézier LinkMap & 分离式合并箭头)

    @ViewBuilder
    private func centralGutter(contentHeight: CGFloat) -> some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor).opacity(0.4)

            // Meld 三次贝塞尔曲面连线
            Canvas { context, size in
                guard let hunks = session.result?.hunks else { return }
                for hunk in hunks {
                    let leftY1 = topPadding + CGFloat(hunk.leftLineRange.lowerBound) * rowHeight
                    let leftY2 = topPadding + CGFloat(max(hunk.leftLineRange.upperBound, hunk.leftLineRange.lowerBound + 1)) * rowHeight
                    let rightY1 = topPadding + CGFloat(hunk.rightLineRange.lowerBound) * rowHeight
                    let rightY2 = topPadding + CGFloat(max(hunk.rightLineRange.upperBound, hunk.rightLineRange.lowerBound + 1)) * rowHeight

                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: leftY1))
                    path.addCurve(
                        to: CGPoint(x: size.width, y: rightY1),
                        control1: CGPoint(x: size.width / 2, y: leftY1),
                        control2: CGPoint(x: size.width / 2, y: rightY1)
                    )
                    path.addLine(to: CGPoint(x: size.width, y: rightY2))
                    path.addCurve(
                        to: CGPoint(x: 0, y: leftY2),
                        control1: CGPoint(x: size.width / 2, y: rightY2),
                        control2: CGPoint(x: size.width / 2, y: leftY2)
                    )
                    path.closeSubpath()

                    let fillColor = hunkFillColor(hunk)
                    context.fill(path, with: .color(fillColor.opacity(hunk.id == session.selectedHunkID ? 0.9 : 0.65)))

                    let strokeColor = hunkStrokeColor(hunk)
                    context.stroke(path, with: .color(strokeColor), lineWidth: 1)
                }
            }

            // 合并操作按钮：左侧向右箭头 (贴近左文件) 与 右侧向左箭头 (贴近右文件)
            if let hunks = session.result?.hunks {
                ForEach(hunks) { hunk in
                    let leftY = topPadding + CGFloat(hunk.leftLineRange.lowerBound) * rowHeight + rowHeight / 2.0
                    let rightY = topPadding + CGFloat(hunk.rightLineRange.lowerBound) * rowHeight + rowHeight / 2.0

                    // 1. 左侧动作：将左侧该差异推向右侧 (→)
                    Button {
                        session.applyHunk(hunk, from: .left)
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentColor)
                            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                    }
                    .buttonStyle(.plain)
                    .help("将左侧内容合并至右侧 (→)")
                    .position(x: 13, y: leftY)

                    // 2. 右侧动作：将右侧该差异拉向左侧 (←)
                    Button {
                        session.applyHunk(hunk, from: .right)
                    } label: {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentColor)
                            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                    }
                    .buttonStyle(.plain)
                    .help("将右侧内容合并至左侧 (←)")
                    .position(x: 45, y: rightY)
                }
            }
        }
        .frame(minHeight: contentHeight)
    }

    // MARK: - 辅助计算方法

    private func diffKind(for side: ComparisonSide, lineIndex: Int) -> DiffHunk.Kind? {
        guard let hunks = session.result?.hunks else { return nil }
        for hunk in hunks {
            let range = side == .left ? hunk.leftLineRange : hunk.rightLineRange
            if range.contains(lineIndex) {
                return hunk.kind
            }
        }
        return nil
    }

    private func marker(for side: ComparisonSide, lineIndex: Int) -> String? {
        guard let kind = diffKind(for: side, lineIndex: lineIndex) else { return nil }
        switch kind {
        case .leftOnly: return "−"
        case .rightOnly: return "+"
        case .modified: return "~"
        }
    }

    private func markerColor(for side: ComparisonSide, lineIndex: Int) -> Color {
        guard let kind = diffKind(for: side, lineIndex: lineIndex) else { return .clear }
        switch kind {
        case .leftOnly: return MeldTheme.deleteBorder(isDark: isDark)
        case .rightOnly: return MeldTheme.insertBorder(isDark: isDark)
        case .modified: return MeldTheme.replaceBorder(isDark: isDark)
        }
    }

    private func rowBackgroundColor(for side: ComparisonSide, lineIndex: Int) -> Color {
        guard let kind = diffKind(for: side, lineIndex: lineIndex) else { return .clear }
        switch kind {
        case .leftOnly: return MeldTheme.deleteBackground(isDark: isDark)
        case .rightOnly: return MeldTheme.insertBackground(isDark: isDark)
        case .modified: return MeldTheme.replaceBackground(isDark: isDark)
        }
    }

    private func hunkFillColor(_ hunk: DiffHunk) -> Color {
        switch hunk.kind {
        case .leftOnly: return MeldTheme.deleteBackground(isDark: isDark)
        case .rightOnly: return MeldTheme.insertBackground(isDark: isDark)
        case .modified: return MeldTheme.replaceBackground(isDark: isDark)
        }
    }

    private func hunkStrokeColor(_ hunk: DiffHunk) -> Color {
        switch hunk.kind {
        case .leftOnly: return MeldTheme.deleteBorder(isDark: isDark)
        case .rightOnly: return MeldTheme.insertBorder(isDark: isDark)
        case .modified: return MeldTheme.replaceBorder(isDark: isDark)
        }
    }
}

// MARK: - 右侧 Overview 标尺

struct SwiftUIOverviewView: View {
    let hunks: [DiffHunk]
    let totalLines: Int

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color(nsColor: .controlBackgroundColor).opacity(0.7)

                let visualLines = max(totalLines, 60)
                let heightScale = proxy.size.height / CGFloat(visualLines)

                ForEach(hunks) { hunk in
                    let startLine = min(hunk.leftLineRange.lowerBound, hunk.rightLineRange.lowerBound)
                    let lineCount = max(hunk.leftLineRange.count, hunk.rightLineRange.count, 1)
                    let y = CGFloat(startLine) * heightScale
                    let height = max(CGFloat(lineCount) * heightScale, 4)

                    RoundedRectangle(cornerRadius: 1)
                        .fill(hunkColor(hunk))
                        .frame(height: height)
                        .offset(y: y)
                }
            }
        }
        .frame(width: 14)
    }

    private func hunkColor(_ hunk: DiffHunk) -> Color {
        switch hunk.kind {
        case .leftOnly: return MeldTheme.deleteBorder(isDark: isDark)
        case .rightOnly: return MeldTheme.insertBorder(isDark: isDark)
        case .modified: return MeldTheme.replaceBorder(isDark: isDark)
        }
    }
}
