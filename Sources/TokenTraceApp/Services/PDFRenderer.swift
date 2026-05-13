import Foundation
import UniformTypeIdentifiers
import WebKit

/// Output format for an exported report.
enum ReportFormat: String, CaseIterable, Identifiable, Codable {
    case html
    case pdf

    var id: String { rawValue }
    var label: String {
        switch self {
        case .html: return "HTML"
        case .pdf:  return "PDF"
        }
    }
    var fileExtension: String { rawValue }
    var utType: UTType {
        switch self {
        case .html: return .html
        case .pdf:  return .pdf
        }
    }
}

/// Off-screen `WKWebView` → PDF pipeline. We render the same HTML the user
/// would get with the HTML export, but pass it through WebKit's `createPDF`
/// so page breaks, font embedding, and chart rasterisation are all handled
/// by the system — no third-party HTML-to-PDF tooling.
@MainActor
enum PDFRenderer {
    enum Error: Swift.Error, LocalizedError {
        case loadFailed(underlying: Swift.Error)
        case renderFailed(underlying: Swift.Error)

        var errorDescription: String? {
            switch self {
            case .loadFailed(let e):    return "Page load failed: \(e.localizedDescription)"
            case .renderFailed(let e):  return "PDF render failed: \(e.localizedDescription)"
            }
        }
    }

    /// Render `html` to a PDF `Data` blob. Internally creates an off-screen
    /// WKWebView, waits for it to finish loading, then calls `createPDF`.
    /// The WebView is retained by the navigation delegate until completion;
    /// both go out of scope together when this function returns.
    static func renderHTMLToPDF(html: String) async throws -> Data {
        // 800-point page width is roughly A-ish — good for reports.
        // WebKit auto-paginates via the template's `@page` rule.
        let frame = NSRect(x: 0, y: 0, width: 800, height: 1000)
        let webView = WKWebView(frame: frame)
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Swift.Error>) in
                waiter.completion = { result in cont.resume(with: result) }
                webView.loadHTMLString(html, baseURL: nil)
            }
        } catch {
            throw Error.loadFailed(underlying: error)
        }

        let config = WKPDFConfiguration()

        do {
            return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Swift.Error>) in
                webView.createPDF(configuration: config) { result in
                    cont.resume(with: result)
                }
            }
        } catch {
            throw Error.renderFailed(underlying: error)
        }
    }
}

/// Minimal `WKNavigationDelegate` that surfaces `didFinish` / `didFail` to a
/// single one-shot continuation.
@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    var completion: ((Result<Void, Swift.Error>) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        completion?(.success(()))
        completion = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Swift.Error) {
        completion?(.failure(error))
        completion = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Swift.Error) {
        completion?(.failure(error))
        completion = nil
    }
}
