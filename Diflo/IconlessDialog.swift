import SwiftUI

struct IconlessDialog<Actions: View>: View {
    let title: LocalizedStringKey
    let message: Text
    private let actions: Actions

    init(title: LocalizedStringKey, message: Text, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            message
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                actions
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 380)
        .interactiveDismissDisabled()
    }
}
