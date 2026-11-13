import SwiftUI
import WebKit

enum PolicyPage: String, Identifiable {
    case terms, privacy
    var id: String { rawValue }
    var title: String { self == .terms ? "Terms of Service" : "Privacy Policy" }
    var url: URL { URL(string: "https://liya-emotional-space.pages.dev/\(rawValue)/")! }
}

struct LegalDocumentView: View {
    @Environment(\.liyaTabBarClearance) private var tabBarClearance
    let page: PolicyPage
    @State private var failed = false
    @State private var attempt = 0
    var body: some View {
        ZStack {
            LiyaBackground()
            VStack(spacing: 0) {
                PageHeader(title: page.title)
                if failed {
                    VStack(spacing: 12) {
                        OfflineNote(text: "This document could not be opened. Please check your connection.")
                        Button("Try again") { failed = false; attempt += 1 }.foregroundStyle(liyaAccent).frame(minHeight: 44)
                    }.padding(20)
                    Spacer()
                } else {
                    LegalHTMLReader(url: page.url, failed: $failed).id(attempt)
                }
            }.padding(.bottom, tabBarClearance)
        }.navigationBarHidden(true)
    }
}

private struct LegalHTMLReader: UIViewRepresentable {
    let url: URL
    @Binding var failed: Bool
    func makeCoordinator() -> Coordinator { Coordinator(failed: $failed) }
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) { }
    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var failed: Bool
        init(failed: Binding<Bool>) { _failed = failed }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed = true }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed = true }
    }
}
