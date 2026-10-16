import SwiftUI

struct BufferStatusBar: View {
    let buffer: EditorBuffer
    let cursor: CursorPosition

    var body: some View {
        HStack(spacing: 16) {
            Text("行 \(cursor.line) · 列 \(cursor.column)")
                .foregroundStyle(.secondary)
                .layoutPriority(1)
                .accessibilityLabel("光标位于第 \(cursor.line) 行，第 \(cursor.column) 列")

            Spacer(minLength: 8)

            ViewThatFits(in: .horizontal) {
                Text("\(buffer.lineCount) 行 · \(buffer.encoding.displayName) · \(buffer.lineEnding.displayName)")
                Text("\(buffer.lineCount) 行")
            }
            .foregroundStyle(.tertiary)
            .help("共 \(buffer.lineCount) 行，编码 \(buffer.encoding.displayName)，换行符 \(buffer.lineEnding.displayName)")
        }
        .font(.system(size: 11).monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}
