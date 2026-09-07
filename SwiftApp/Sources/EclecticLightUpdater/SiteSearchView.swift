import SwiftUI
import WebKit

struct SiteSearchView: View {
    let appName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search Eclectic Light")
                        .font(.headline)
                    Text("Results for \(appName) are informational until a verified ZIP is added to the catalog.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)

            Divider()
            WebsiteSearchWebView(url: searchURL)
        }
    }

    private var searchURL: URL {
        var components = URLComponents(string: "https://eclecticlight.co/")!
        components.queryItems = [URLQueryItem(name: "s", value: appName)]
        return components.url!
    }
}

private struct WebsiteSearchWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsMagnification = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}
