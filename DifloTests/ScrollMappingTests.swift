import Foundation
import CoreGraphics
import Testing
@testable import Diflo

struct ScrollMappingTests {
    @Test func actualLineHeightDefinesAnchorFraction() {
        let geometry = DiffViewportGeometry(visibleLines: 2..<4, lineRects: [2: CGRect(x: 0, y: 70, width: 100, height: 30), 3: CGRect(x: 0, y: 100, width: 100, height: 18)])
        #expect(geometry.linePosition(at: 85) == 2.5)
        #expect(geometry.y(for: 3.5) == 109)
    }
}
