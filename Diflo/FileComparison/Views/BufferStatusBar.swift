import SwiftUI

struct BufferStatusBar: View {
    let buffer: EditorBuffer
    let cursor: CursorPosition

    var body: some View {
        HStack(spacing: 12) {
            Text(buffer.encoding.displayName)
            Text(buffer.lineEnding.displayName)
            Spacer(minLength: 8)
            Text("\(buffer.lineCount) 行")
            Text("行 \(cursor.line)，列 \(cursor.column)")
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}
