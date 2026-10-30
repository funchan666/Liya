import SwiftUI
import PDFKit

enum PolicyPage: String, Identifiable {
    case terms, privacy
    var id: String { rawValue }
    var title: String { self == .terms ? "Terms of Service" : "Privacy Policy" }
    var url: URL {
        URL(string: "https://hymfjhuglaqoftrcxfjx.supabase.co/storage/v1/object/public/liya-legal/\(rawValue).pdf")!
    }
}

struct LegalDocumentView: View {
    let page: PolicyPage
    @State private var document: PDFDocument?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        ZStack {
            LiyaBackground()
            VStack(spacing: 0) {
                PageHeader(title: page.title)
                if let document {
                    PDFReader(document: document)
                } else if failed {
                    VStack(spacing: 12) {
                        OfflineNote(text: "This document could not be opened. Please check your connection.")
                        Button("Try again") { attempt += 1 }.foregroundStyle(liyaAccent).frame(minHeight: 44)
                    }.padding(20)
                    Spacer()
                } else {
                    Text("Opening document…").foregroundStyle(liyaInk).padding(20)
                    Spacer()
                }
            }
        }.navigationBarHidden(true)
            .task(id: attempt) { await load() }
    }

    @MainActor private func load() async {
        document = nil; failed = false
        do {
            let (data, response) = try await URLSession.shared.data(from: page.url)
            guard !Task.isCancelled, let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode), data.count <= 5_000_000,
                  data.starts(with: Data("%PDF-".utf8)), let pdf = PDFDocument(data: data) else {
                if !Task.isCancelled { failed = true }
                return
            }
            document = pdf
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

private struct PDFReader: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = document
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}
