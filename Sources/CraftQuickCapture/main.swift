import AppKit

// Hidden diagnostic: `CraftQuickCapture --selftest-table <collectionId>`
// exercises the table pipeline (schema fetch + row insert) and exits.
if let idx = CommandLine.arguments.firstIndex(of: "--selftest-table"),
   CommandLine.arguments.count > idx + 1 {
    let collectionId = CommandLine.arguments[idx + 1]
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            let client = CraftClient()
            let schema = try await client.collectionSchema(id: collectionId)
            print("schema columns: " + schema.columns.map {
                "\($0.key)(\($0.type)\($0.isTitle ? ",title" : ""))\($0.options.isEmpty ? "" : "=" + $0.options.joined(separator: "|"))"
            }.joined(separator: " "))
            var values: [String: String] = [schema.titleKey: "Selftest row \"quoted\" — \(Date())"]
            for col in schema.columns where !col.isTitle {
                values[col.key] = col.options.first ?? "selftest \(col.key)\nsecond line"
            }
            try await client.addCollectionItem(schema: schema, values: values)
            print("selftest-table OK")
        } catch {
            print("selftest-table FAILED: \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(0)
}

// Hidden diagnostic: `CraftQuickCapture --selftest <pageId> [imagePath]`
// exercises the exact save pipeline (image relay + append) and exits.
if let idx = CommandLine.arguments.firstIndex(of: "--selftest"),
   CommandLine.arguments.count > idx + 1 {
    let pageId = CommandLine.arguments[idx + 1]
    let imagePath = CommandLine.arguments.count > idx + 2 ? CommandLine.arguments[idx + 2] : nil
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            let client = CraftClient()
            var markdown = "## Selftest heading\n\nSelf-test capture \(Date())\nsoft-break line\n\n- [ ] selftest task"
            if let imagePath {
                let data = try Data(contentsOf: URL(fileURLWithPath: imagePath))
                let url = try await ImageUploader.upload(data, filename: "selftest.png")
                print("uploaded image: \(url)")
                markdown += "\n\n![image](\(url))"
            }
            try await client.appendBlocks(pageId: pageId, markdown: markdown)
            print("selftest OK")
        } catch {
            print("selftest FAILED: \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
