import SwiftUI

struct ComparisonView: View {
    let session: ComparisonSession

    var body: some View {
        ComparisonWorkspaceView(session: session)
    }
}
