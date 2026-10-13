import SwiftUI

struct BufferStatusBar: View {
    let buffer: EditorBuffer
    let cursor: CursorPosition

    var body: some View {
        HStack(spacing: 10) {
            Text(buffer.encoding.displayName)
            Text(buffer.lineEnding.displayName)
            Text("纯文本")
            Spacer(minLength: 8)
            Text("\(buffer.lineCount) 行")
            Text("行 \(cursor.line)，列 \(cursor.column)")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
