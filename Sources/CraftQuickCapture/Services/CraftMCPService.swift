import Foundation
import AppKit

// MARK: - SendStatus

enum SendStatus: Equatable {
    case idle
    case sending
    case success
    case failure(String)
}

// MARK: - Errors

enum CraftCaptureError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int, String)
    case mcpError(String)
    case imageConversionFailed
    case imageUploadFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:            return "URL MCP invalide dans les préférences"
        case .invalidResponse:       return "Réponse invalide du serveur MCP"
        case .httpError(let c, _):   return "Erreur HTTP \(c) — vérifiez votre lien MCP Craft"
        case .mcpError(let m):       return m
        case .imageConversionFailed: return "Impossible de convertir l'image en JPEG"
        case .imageUploadFailed:     return "Upload de l'image échoué (tmpfiles.org et catbox inaccessibles)"
        }
    }
}

// MARK: - App Config

/// Stored at ~/Library/Application Support/CraftQuickCapture/config.json
struct AppConfig: Codable {
    var mcpEndpoint: String
    /// Carbon modifier mask (UInt32): cmdKey=0x100, optionKey=0x800, shiftKey=0x200, ctrlKey=0x1000
    var hotkeyModifiers: UInt32
    /// Carbon key code (UInt32): kVK_Space=0x31
    var hotkeyKeyCode: UInt32

    static let `default` = AppConfig(
        mcpEndpoint: "https://mcp.craft.do/links/7o8lSn7vmMD/mcp",
        hotkeyModifiers: 0x0100 | 0x0800, // cmdKey | optionKey  → ⌥⌘
        hotkeyKeyCode:   0x31              // kVK_Space           → Space
    )

    static func loadOrDefault() -> AppConfig {
        guard
            let data = try? Data(contentsOf: configURL),
            let cfg  = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return .default }
        return cfg
    }

    func save() {
        let dir = Self.configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.configURL, options: .atomic)
        }
    }

    private static var configURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CraftQuickCapture/config.json")
    }
}

// MARK: - CraftMCPService

/// Stateless JSON-RPC client for the Craft MCP endpoint.
/// Each save is a single POST — no session management needed.
/// See: https://mcp.craft.do
@MainActor
final class CraftMCPService: ObservableObject {

    @Published var documents: [CraftDocument] = []
    @Published var isLoading = false
    @Published var sendStatus: SendStatus = .idle
    @Published var connectionError: String?

    @Published var config: AppConfig {
        didSet { config.save() }
    }

    var mcpEndpoint: String {
        get { config.mcpEndpoint }
        set { config.mcpEndpoint = newValue }
    }

    private var requestCounter = 0
    private lazy var urlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 90
        return URLSession(configuration: cfg)
    }()

    init() {
        self.config = AppConfig.loadOrDefault()
        // Seed from cache immediately so the picker is usable before first fetch
        if let cache = DocumentCache.load() {
            self.documents = cache.documents
        }
    }

    // MARK: - Document Fetching

    /// Load documents from cache; refresh in background if stale.
    func loadDocuments() async {
        if let cache = DocumentCache.load(), !cache.isStale {
            documents = cache.documents
            return
        }
        await refreshDocuments()
    }

    /// Force-refresh the document list (cursor-paginated).
    func refreshDocuments() async {
        guard !isLoading else { return }
        isLoading = true
        connectionError = nil
        defer { isLoading = false }

        var allDocs: [CraftDocument] = []
        var cursor: String? = nil

        repeat {
            var query = "list all documents; include folder name for each document"
            if let c = cursor { query += " --cursor \(c)" }

            do {
                let text = try await callTool(name: "craft_read", arguments: ["query": query])
                let (parsed, nextCursor) = DocumentParser.parse(text)
                allDocs.append(contentsOf: parsed)
                cursor = nextCursor
            } catch {
                connectionError = error.localizedDescription
                print("[CraftCapture] fetchDocuments page error: \(error)")
                cursor = nil
                break
            }
        } while cursor != nil

        if !allDocs.isEmpty {
            documents = allDocs
            DocumentCache(documents: allDocs, lastUpdated: Date()).save()
        } else if documents.isEmpty {
            connectionError = connectionError ?? "Aucun document trouvé — vérifiez votre lien MCP Craft"
        }
    }

    // MARK: - Send Text

    func sendText(_ text: String, to document: CraftDocument) async {
        sendStatus = .sending

        // Craft API requires REAL newline characters, not escaped \n
        let query: String
        if document.hasValidId {
            query = "Add a new text block to document \"\(document.title)\" (documentId: \(document.id)):\n\(text)"
        } else {
            query = "Add a new text block to document \"\(document.title)\":\n\(text)"
        }

        do {
            _ = try await callTool(name: "craft_write", arguments: ["query": query])
            sendStatus = .success
        } catch {
            sendStatus = .failure(error.localizedDescription)
        }
    }

    // MARK: - Send Image

    func sendImage(_ image: NSImage, caption: String = "", to document: CraftDocument) async {
        sendStatus = .sending

        do {
            guard let jpegData = image.jpegRepresentation() else {
                throw CraftCaptureError.imageConversionFailed
            }

            // Craft's API only ingests images from PUBLIC HTTPS URLs.
            // We relay through tmpfiles.org (60 min retention);
            // Craft copies to its own CDN at save time so expiry doesn't matter.
            let publicURL = try await relayImage(jpegData)

            let altText = caption.isEmpty ? "image" : caption
            var blockContent = "![\(altText)](\(publicURL))"
            if !caption.trimmingCharacters(in: .whitespaces).isEmpty {
                blockContent = caption + "\n" + blockContent
            }

            let query: String
            if document.hasValidId {
                query = "Add a new block to document \"\(document.title)\" (documentId: \(document.id)):\n\(blockContent)"
            } else {
                query = "Add a new block to document \"\(document.title)\":\n\(blockContent)"
            }

            _ = try await callTool(name: "craft_write", arguments: ["query": query])
            sendStatus = .success

        } catch {
            sendStatus = .failure(error.localizedDescription)
        }
    }

    // MARK: - Image Relay

    /// Uploads image data to a temporary public host and returns the direct URL.
    /// Primary: tmpfiles.org · Fallback: litterbox.catbox.moe
    private func relayImage(_ data: Data) async throws -> String {
        if let url = try? await uploadTmpFiles(data) { return url }
        if let url = try? await uploadCatbox(data)   { return url }
        throw CraftCaptureError.imageUploadFailed
    }

    private func uploadTmpFiles(_ data: Data) async throws -> String? {
        let url = URL(string: "https://tmpfiles.org/api/v1/upload")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = buildMultipart(boundary: boundary, field: "file",
                                      filename: "capture.jpg", mimeType: "image/jpeg", data: data)

        let (body, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }

        // Response: {"status":"success","data":{"url":"https://tmpfiles.org/XXXXX/capture.jpg"}}
        if let json     = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let dataObj  = json["data"] as? [String: Any],
           var urlStr   = dataObj["url"] as? String {
            // Convert view URL to direct-download URL
            urlStr = urlStr.replacingOccurrences(of: "tmpfiles.org/", with: "tmpfiles.org/dl/")
            return urlStr
        }
        return nil
    }

    private func uploadCatbox(_ data: Data) async throws -> String? {
        let url = URL(string: "https://litterbox.catbox.moe/resources/internals/api.php")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // reqtype field
        body.append(multipartField(boundary: boundary, name: "reqtype", value: "fileupload"))
        // time field (1 hour retention)
        body.append(multipartField(boundary: boundary, name: "time", value: "1h"))
        // file field
        body.append(buildMultipart(boundary: boundary, field: "fileToUpload",
                                   filename: "capture.jpg", mimeType: "image/jpeg", data: data))
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (responseData, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        let result = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespaces)
        // catbox returns the direct URL as plain text
        return result?.hasPrefix("http") == true ? result : nil
    }

    // MARK: - Multipart helpers

    private func buildMultipart(boundary: String, field: String,
                                 filename: String, mimeType: String, data: Data) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\n"
            .data(using: .utf8)!
        )
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        return body
    }

    private func multipartField(boundary: String, name: String, value: String) -> Data {
        var d = Data()
        d.append("--\(boundary)\r\n".data(using: .utf8)!)
        d.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        d.append("\(value)\r\n".data(using: .utf8)!)
        return d
    }

    // MARK: - MCP Core (stateless — single POST per operation)

    private func callTool(name: String, arguments: [String: Any]) async throws -> String {
        guard let url = URL(string: config.mcpEndpoint) else {
            throw CraftCaptureError.invalidURL
        }

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id":      nextId(),
            "method":  "tools/call",
            "params":  ["name": name, "arguments": arguments]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",                     forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: req)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let preview = String(data: data, encoding: .utf8) ?? ""
            throw CraftCaptureError.httpError(http.statusCode, preview)
        }

        // Some endpoints return SSE; unwrap to bare JSON
        let jsonData = unwrapSSE(data: data, response: response)

        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? "(non-UTF8)"
            print("[CraftCapture] Unexpected response: \(preview)")
            throw CraftCaptureError.invalidResponse
        }

        // Propagate MCP-level errors
        if let err = json["error"] as? [String: Any],
           let msg = err["message"] as? String {
            throw CraftCaptureError.mcpError(msg)
        }

        guard let result = json["result"] as? [String: Any] else { return "" }

        if let content = result["content"] as? [[String: Any]] {
            return content.compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }.joined(separator: "\n")
        }

        return ""
    }

    /// Extracts the last JSON payload from an SSE `data: {...}` stream.
    private func unwrapSSE(data: Data, response: URLResponse) -> Data {
        guard
            let http = response as? HTTPURLResponse,
            let ct   = http.value(forHTTPHeaderField: "Content-Type"),
            ct.contains("text/event-stream"),
            let text = String(data: data, encoding: .utf8)
        else { return data }

        for line in text.components(separatedBy: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data: ") else { continue }
            let payload = String(trimmed.dropFirst(6))
            guard payload != "[DONE]", !payload.isEmpty else { continue }
            if let d = payload.data(using: .utf8) { return d }
        }
        return data
    }

    private func nextId() -> Int {
        requestCounter += 1
        return requestCounter
    }
}

// MARK: - NSImage JPEG helper

extension NSImage {
    func jpegRepresentation(compressionFactor: CGFloat = 0.85) -> Data? {
        guard let tiff   = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor])
    }
}

// MARK: - Document Parser

/// Parses free-text MCP responses into `[CraftDocument]`.
/// Returns (documents, nextCursor?) — cursor extracted from "Next page: XXX" trailer.
///
/// Handled formats:
///   • Markdown link: [Title](craftdocs://openDoc?id=XXX&spaceId=YYY) — Folder
///   • Bold meta:     **Title** | Folder: X | ID: abc123
///   • Plain sep:     Title — Folder  /  Title | Folder  /  Title - Folder
///   • Raw title only
enum DocumentParser {

    static func parse(_ text: String) -> ([CraftDocument], String?) {
        guard !text.isEmpty else { return ([], nil) }

        var results:    [CraftDocument] = []
        var seenTitles: Set<String>     = []
        var nextCursor: String?         = nil

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Cursor trailer from Craft API: "Next page: <token>"
            if trimmed.lowercased().hasPrefix("next page:") {
                let tok = String(trimmed.dropFirst("next page:".count)).trimmingCharacters(in: .whitespaces)
                nextCursor = tok.isEmpty ? nil : tok
                continue
            }

            if let doc = parseLine(trimmed) {
                let key = doc.title.lowercased()
                if !seenTitles.contains(key) {
                    seenTitles.insert(key)
                    results.append(doc)
                }
            }
        }

        let sorted = results.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        return (sorted, nextCursor)
    }

    // MARK: - Line parsers

    private static func parseLine(_ line: String) -> CraftDocument? {
        guard !line.isEmpty,
              !line.hasPrefix("#"),
              !line.hasPrefix("---"),
              !line.hasPrefix("===")
        else { return nil }

        // Strip list prefix (-, *, +, "N. ")
        var content = line
        for pfx in ["- ", "* ", "+ "] {
            if content.hasPrefix(pfx) { content = String(content.dropFirst(pfx.count)); break }
        }
        if let dotIdx = content.firstIndex(of: "."),
           content[content.startIndex..<dotIdx].allSatisfy(\.isNumber) {
            content = String(content[content.index(after: dotIdx)...])
                .trimmingCharacters(in: .whitespaces)
        }
        guard !content.isEmpty else { return nil }

        if let doc = parseCraftLink(content)    { return doc }
        if let doc = parseBoldWithMeta(content) { return doc }
        if let doc = parsePlainSeparated(content) { return doc }

        // Last resort: treat whole line as title
        let title = stripMarkdown(content)
        guard title.count >= 2, !title.hasPrefix("http") else { return nil }
        return CraftDocument(id: UUID().uuidString, title: title,
                             folderName: nil, spaceId: nil, hasValidId: false)
    }

    /// [Title](craftdocs://openDoc?id=X&spaceId=Y) — rest
    private static func parseCraftLink(_ text: String) -> CraftDocument? {
        guard
            let regex = try? NSRegularExpression(
                pattern: #"\[(.+?)\]\((craftdocs://[^)]+)\)(.*)"#),
            let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }

        let ns      = text as NSString
        let title   = ns.substring(with: m.range(at: 1))
        let urlStr  = ns.substring(with: m.range(at: 2))
        let rest    = ns.substring(with: m.range(at: 3))

        var docId     = UUID().uuidString
        var spaceId:  String?
        var validId   = false

        if let url   = URL(string: urlStr),
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let id = comps.queryItems?.first(where: { $0.name == "id" })?.value {
                docId = id; validId = true
            }
            spaceId = comps.queryItems?.first(where: { $0.name == "spaceId" })?.value
        }

        return CraftDocument(id: docId, title: title,
                             folderName: cleanFolder(rest), spaceId: spaceId, hasValidId: validId)
    }

    /// **Title** | Folder: X | ID: abc
    private static func parseBoldWithMeta(_ text: String) -> CraftDocument? {
        guard
            let regex = try? NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#),
            let m     = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }

        let title = (text as NSString).substring(with: m.range(at: 1))

        var docId   = UUID().uuidString
        var validId = false
        if let idRx = try? NSRegularExpression(pattern: #"(?:id|ID|Id):\s*([a-zA-Z0-9\-_]{6,})"#),
           let idM  = idRx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            docId   = (text as NSString).substring(with: idM.range(at: 1))
            validId = true
        }

        let folder = cleanFolder(
            text.replacingOccurrences(of: "**\(title)**", with: "")
                .replacingOccurrences(of: #"(?:id|ID|Id):\s*[a-zA-Z0-9\-_]+"#, with: "",
                                      options: .regularExpression)
        )
        return CraftDocument(id: docId, title: title,
                             folderName: folder, spaceId: nil, hasValidId: validId)
    }

    /// Title — Folder  /  Title | Folder  /  Title - Folder
    private static func parsePlainSeparated(_ text: String) -> CraftDocument? {
        for sep in [" — ", " | ", " - "] {
            if let r = text.range(of: sep) {
                let title  = stripMarkdown(String(text[..<r.lowerBound]))
                let folder = stripMarkdown(String(text[r.upperBound...]))
                guard !title.isEmpty else { continue }
                return CraftDocument(id: UUID().uuidString, title: title,
                                     folderName: folder.isEmpty ? nil : folder,
                                     spaceId: nil, hasValidId: false)
            }
        }
        return nil
    }

    private static func cleanFolder(_ text: String) -> String? {
        let clean = text
            .trimmingCharacters(in: .init(charactersIn: " -|/()[]"))
            .replacingOccurrences(of: #"(?:folder|Folder|dossier|space|Space):\s*"#,
                                  with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? nil : clean
    }

    private static func stripMarkdown(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*",  with: "")
            .replacingOccurrences(of: "`",  with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
