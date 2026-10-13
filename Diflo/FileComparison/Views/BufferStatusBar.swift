import SwiftUI

struct BufferStatusBar: View {
    let buffer: EditorBuffer
    let cursor: CursorPosition

    var body: some View {
        HStack(spacing: 14) {
            Text(buffer.encoding.displayName)
            Text(buffer.lineEnding.displayName)
            Text("纯文本")
            Spacer()
            Text("\(buffer.lineCount) 行")
            Text("行 \(cursor.line)，列 \(cursor.column)")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
