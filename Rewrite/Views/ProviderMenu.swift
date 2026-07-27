import SwiftUI

struct ProviderMenu: View {
    @EnvironmentObject private var model: RewriteViewModel

    var body: some View {
        Menu {
            ForEach(RewriteProviderChoice.allCases) { provider in
                Button {
                    model.selectProvider(provider)
                } label: {
                    Label(provider.title, systemImage: provider.symbolName)
                    if model.provider == provider {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            Button("Check Again") {
                Task { await model.refreshStatus() }
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: model.status.symbolName)
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.status.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(model.provider.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(model.status.detail)
        .accessibilityLabel(
            "\(model.provider.title). \(model.status.title). \(model.status.detail)"
        )
    }

    private var statusColor: Color {
        switch model.status.state {
        case .checking: .secondary
        case .ready: .green
        case .waiting: .orange
        case .unavailable: .red
        }
    }
}
