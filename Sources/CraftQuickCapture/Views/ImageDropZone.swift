import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ImageDropZone: View {
    @Binding var image: NSImage?
    @Binding var caption: String

    @State private var isDragTargeted = false

    var body: some View {
        Group {
            if let image {
                previewView(image)
            } else {
                dropTargetView
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDragTargeted, perform: handleDrop)
    }

    // MARK: - Drop target

    private var dropTargetView: some View {
        VStack(spacing: 8) {
            Image(systemName: isDragTargeted ? "photo.badge.plus.fill" : "photo.badge.plus")
                .font(.system(size: 30))
                .foregroundStyle(isDragTargeted ? Color.accentColor : .tertiary)
                .scaleEffect(isDragTargeted ? 1.12 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragTargeted)

            Text("Glissez une image ici")
                .font(.system(.subheadline))
                .foregroundStyle(.tertiary)

            Button("Parcourir…") { pickImage() }
                .buttonStyle(.plain)
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDragTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { pickImage() }
    }

    // MARK: - Preview

    private func previewView(_ img: NSImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                )

            Button(action: { image = nil; caption = "" }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .background(Circle().fill(.background).padding(2))
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }

    // MARK: - Helpers

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            // Try loading as NSImage directly
            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                    if let img = obj as? NSImage {
                        DispatchQueue.main.async { self.image = img }
                    }
                }
                return true
            }
            // Try loading as file URL
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let u = item as? URL {
                        url = u
                    } else {
                        url = nil
                    }
                    if let url, let img = NSImage(contentsOf: url) {
                        DispatchQueue.main.async { self.image = img }
                    }
                }
                return true
            }
        }
        return false
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP, .heic, .bmp, .tiff]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url,
           let img = NSImage(contentsOf: url) {
            image = img
        }
    }
}
