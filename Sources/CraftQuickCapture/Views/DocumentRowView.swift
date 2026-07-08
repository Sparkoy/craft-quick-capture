import SwiftUI

struct DocumentRowView: View {
    let document: CraftDocument
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "doc.text.fill" : "doc.text")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 18, alignment: .center)

            Text(document.title)
                .font(.system(.subheadline))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let folder = document.folderName {
                Text(folder)
                    .font(.system(.caption))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                        .padding(.horizontal, 5)
                }
            }
        )
        .contentShape(Rectangle())
    }
}
