import SwiftUI

struct SettingsView: View {

    @ObservedObject var service: CraftMCPService
    @State private var endpointDraft: String = ""
    @State private var saveConfirmed = false

    var body: some View {
        Form {
            // MARK: Craft Connection
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lien MCP Craft")
                        .font(.headline)
                    Text("Générez ce lien dans Craft → Réglages → AI / Imagine → "Connecter un assistant AI".\nTraitez-le comme un mot de passe : quiconque le possède peut lire et écrire dans votre espace.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("https://mcp.craft.do/links/…/mcp",
                              text: $endpointDraft)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .onAppear  { endpointDraft = service.mcpEndpoint }
                        .onSubmit  { applyEndpoint() }

                    HStack {
                        Button("Enregistrer") { applyEndpoint() }
                            .buttonStyle(.borderedProminent)

                        if saveConfirmed {
                            Label("Enregistré", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                                .transition(.opacity)
                        }
                    }
                }
            }

            // MARK: Documents
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Documents")
                        .font(.headline)

                    HStack {
                        Text("\(service.documents.count) document(s) en cache")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            Task { await service.refreshDocuments() }
                        } label: {
                            Label(
                                service.isLoading ? "Chargement…" : "Rafraîchir",
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .disabled(service.isLoading)
                    }

                    if let err = service.connectionError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }

            // MARK: Hotkey
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Raccourci clavier")
                        .font(.headline)
                    HStack(spacing: 4) {
                        Text("Raccourci par défaut :")
                        Text("⌥⌘Space")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                    Text("La personnalisation du raccourci est prévue dans une prochaine version.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Privacy note
            Section {
                Text("Les images sont relayées via tmpfiles.org (60 min) avant d'être importées par Craft sur son propre CDN. Le lien temporaire expire sans conséquence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }

    private func applyEndpoint() {
        let trimmed = endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        service.mcpEndpoint = trimmed
        withAnimation { saveConfirmed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { saveConfirmed = false }
        }
        // Refresh with new endpoint
        Task { await service.refreshDocuments() }
    }
}
