import SwiftUI

struct CaptureView: View {
    @ObservedObject var service: CraftMCPService
    let onDismiss: () -> Void

    // Input state
    @State private var inputText = ""
    @State private var droppedImage: NSImage?
    @State private var imageCaption = ""
    @State private var inputMode: InputMode = .text

    // Document picker state
    @State private var searchQuery = ""
    @State private var selectedDocument: CraftDocument?

    // UI state
    @State private var showSuccess = false
    @FocusState private var textFocused: Bool

    enum InputMode: String, CaseIterable {
        case text, image
        var icon: String { self == .text ? "text.alignleft" : "photo" }
        var label: String { self == .text ? "Texte" : "Image" }
    }

    // MARK: - Derived

    private var filteredDocs: [CraftDocument] {
        guard !searchQuery.isEmpty else { return service.documents }
        let q = searchQuery.lowercased()
        return service.documents.filter {
            $0.title.lowercased().contains(q) ||
            ($0.folderName?.lowercased().contains(q) ?? false)
        }
    }

    private var canSend: Bool {
        guard selectedDocument != nil else { return false }
        switch inputMode {
        case .text:  return !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image: return droppedImage != nil
        }
    }

    private var isSending: Bool {
        if case .sending = service.sendStatus { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            panelBackground

            VStack(spacing: 0) {
                headerBar
                divider
                inputSection
                divider
                documentSection
                divider
                footerBar
            }

            if showSuccess { successOverlay }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.38), radius: 30, x: 0, y: 10)
        .frame(width: 500, height: 570)
        .onAppear {
            textFocused = true
            if service.documents.isEmpty {
                Task { await service.loadDocuments() }
            }
        }
        .onChange(of: service.sendStatus) { _, status in
            if case .success = status {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { showSuccess = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    onDismiss()
                    resetState()
                }
            }
        }
        // Auto-switch to image mode when something is dropped
        .onChange(of: droppedImage) { _, img in
            if img != nil { inputMode = .image }
        }
    }

    // MARK: - Background

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )
    }

    private var divider: some View {
        Divider().opacity(0.18)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            // App identity
            HStack(spacing: 7) {
                Image(systemName: "square.and.pencil")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                    .font(.system(size: 15, weight: .semibold))
                Text("CraftCapture")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }

            Spacer()

            // Text / Image mode toggle
            HStack(spacing: 0) {
                ForEach(InputMode.allCases, id: \.self) { mode in
                    Button(action: { withAnimation(.easeInOut(duration: 0.15)) { inputMode = mode } }) {
                        Label(mode.label, systemImage: mode.icon)
                            .labelStyle(.iconOnly)
                            .font(.system(size: 13))
                            .frame(width: 34, height: 26)
                            .background(
                                inputMode == mode
                                    ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.18))
                                    : nil
                            )
                            .foregroundStyle(inputMode == mode ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))

            // Dismiss
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Input

    @ViewBuilder
    private var inputSection: some View {
        if inputMode == .text {
            textInputView
        } else {
            imageInputView
        }
    }

    private var textInputView: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $inputText)
                .font(.system(.body))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 120, maxHeight: 140)
                .focused($textFocused)

            if inputText.isEmpty {
                Text("Une pensée, une note, une idée…")
                    .font(.system(.body))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .allowsHitTesting(false)
            }
        }
    }

    private var imageInputView: some View {
        VStack(spacing: 8) {
            ImageDropZone(image: $droppedImage, caption: $imageCaption)
                .frame(height: 100)

            if droppedImage != nil {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $imageCaption)
                        .font(.system(.footnote))
                        .scrollContentBackground(.hidden)
                        .frame(height: 30)

                    if imageCaption.isEmpty {
                        Text("Légende (optionnel)…")
                            .font(.system(.footnote))
                            .foregroundStyle(.quaternary)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 120, maxHeight: 140)
    }

    // MARK: - Document Picker

    private var documentSection: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)

                TextField("Rechercher un document…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(.subheadline))

                if service.isLoading {
                    ProgressView().scaleEffect(0.55)
                }

                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.quaternary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider().opacity(0.12)

            // List
            ScrollView {
                LazyVStack(spacing: 0) {
                    listContent
                }
            }
            .frame(maxHeight: 222)
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if service.isLoading && service.documents.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("Chargement des documents…")
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
            }
            .padding()
        } else if !service.documents.isEmpty && filteredDocs.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                Text("Aucun résultat pour « \(searchQuery) »")
                    .font(.system(.subheadline))
                    .foregroundStyle(.tertiary)
            }
            .padding()
        } else if service.documents.isEmpty && !service.isLoading {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
                Text("Aucun document trouvé")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                if let err = service.connectionError {
                    Text(err)
                        .font(.system(.caption))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Button("Réessayer") {
                    Task { await service.refreshDocuments() }
                }
                .buttonStyle(.borderless)
                .font(.system(.caption, weight: .medium))
                .padding(.top, 4)
            }
            .padding()
        } else {
            ForEach(filteredDocs) { doc in
                DocumentRowView(
                    document: doc,
                    isSelected: selectedDocument?.id == doc.id
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        selectedDocument = doc
                    }
                }

                if doc.id != filteredDocs.last?.id {
                    Divider()
                        .padding(.leading, 42)
                        .opacity(0.10)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 10) {
            // Selected doc indicator
            Group {
                if let doc = selectedDocument {
                    Label(doc.title, systemImage: "checkmark.circle.fill")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Sélectionner un document")
                        .font(.system(.caption))
                        .foregroundStyle(.quaternary)
                }
            }

            Spacer()

            // Error badge
            if case .failure(let msg) = service.sendStatus {
                Text(msg)
                    .font(.system(.caption))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .frame(maxWidth: 200)
            }

            // Send button
            Button(action: doSend) {
                if isSending {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.65)
                        Text("Envoi…").font(.system(.subheadline, weight: .semibold))
                    }
                } else {
                    Label("Envoyer", systemImage: "arrow.up.circle.fill")
                        .font(.system(.subheadline, weight: .semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!canSend || isSending)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Success overlay

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()

            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.green)
                Text("Envoyé dans Craft !")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThickMaterial)
                    .shadow(radius: 12)
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .center)))
    }

    // MARK: - Actions

    private func doSend() {
        guard let doc = selectedDocument else { return }
        Task {
            switch inputMode {
            case .text:
                await service.sendText(
                    inputText.trimmingCharacters(in: .whitespacesAndNewlines),
                    to: doc
                )
            case .image:
                if let img = droppedImage {
                    await service.sendImage(img, caption: imageCaption, to: doc)
                }
            }
        }
    }

    private func resetState() {
        inputText = ""
        droppedImage = nil
        imageCaption = ""
        selectedDocument = nil
        searchQuery = ""
        showSuccess = false
        service.sendStatus = .idle
    }
}
