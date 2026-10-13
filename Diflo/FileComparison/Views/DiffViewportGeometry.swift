import Foundation
import CoreGraphics

nonisolated struct DiffViewportGeometry: Equatable {
    var visibleLines: Range<Int> = 0..<0
    var lineRects: [Int: CGRect] = [:]

    func linePosition(at y: CGFloat) -> Double? {
        guard let entry = lineRects.min(by: { abs($0.value.midY - y) < abs($1.value.midY - y) }) else { return nil }
        return Double(entry.key) + min(1, max(0, (y - entry.value.minY) / max(1, entry.value.height)))
    }

    func y(for position: Double) -> CGFloat? {
        let line = Int(floor(position))
        if let rect = lineRects[line] { return rect.minY + CGFloat(position - Double(line)) * rect.height }
        if position == Double(line), let preceding = lineRects[line - 1] { return preceding.maxY }
        return nil
    }

    func rect(for range: Range<Int>) -> CGRect? {
        if range.isEmpty, let y = y(for: Double(range.lowerBound)) { return CGRect(x: 0, y: y, width: 1, height: 2) }
        return lineRects.filter { range.contains($0.key) }.values.reduce(nil as CGRect?) { result, rect in result.map { $0.union(rect) } ?? rect }
    }
}
