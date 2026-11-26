import SwiftUI
import WebKit

@main
struct GoogleWebViewApp: App {
    @State private var page = "Loading Google…"

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Text(page)
                    .font(.footnote)
                    .lineLimit(1)
                    .padding(8)
                    .accessibilityLabel(page)
                    .accessibilityIdentifier("loaded-page")
                Divider()
                GooglePage(address: $page)
            }
        }
    }
}

private struct GooglePage: UIViewRepresentable {
    @Binding var address: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: "https://www.google.com/?hl=en") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(address: $address)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var address: String

        init(address: Binding<String>) {
            _address = address
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            address = webView.url?.absoluteString ?? "Page unavailable"
        }
    }
}
