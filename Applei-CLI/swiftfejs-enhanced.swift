import WebKit
import Foundation
import AppKit

// MARK: - Types

enum OutputMode: String {
    case html
    case text
    case links
    case json
    case scripts
}

struct FetchConfig {
    let url: URL
    let waitTime: TimeInterval
    let timeout: TimeInterval
    let mode: OutputMode
    let customScript: String?
}

struct PageResult: Codable {
    let title: String
    let url: String
    let content: String
    let links: [LinkInfo]?
    let scripts: [ScriptInfo]?
    let metadata: [String: String]?
}

struct LinkInfo: Codable {
    let text: String
    let href: String
}

struct ScriptInfo: Codable {
    let src: String
    let type: String
}

// MARK: - JavaScript Scripts

struct Scripts {
    static let extractText = """
        (function() {
            const clone = document.body.cloneNode(true);
            clone.querySelectorAll('script, style, noscript, [hidden], nav, header, footer, .nav, .header, .footer, [role="navigation"]').forEach(e => e.remove());
            return clone.innerText.replace(/\\s+/g, ' ').trim();
        })()
    """
    
    static let extractLinks = """
        Array.from(document.querySelectorAll('a')).map(a => ({
            text: a.innerText.trim().replace(/\\s+/g, ' '),
            href: a.href
        })).filter(l => l.href && !l.href.startsWith('javascript:'))
    """
    
    static let extractScripts = """
        Array.from(document.querySelectorAll('script')).map(s => ({
            src: s.src || '',
            type: s.type || 'text/javascript'
        }))
    """
    
    static let extractMetadata = """
        (function() {
            const meta = {};
            Array.from(document.querySelectorAll('meta')).forEach(m => {
                const key = m.getAttribute('name') || m.getAttribute('property');
                const val = m.getAttribute('content');
                if (key && val) meta[key] = val;
            });
            return meta;
        })()
    """
    
    static let extractAllJSON = """
        (function() {
            const clone = document.body.cloneNode(true);
            clone.querySelectorAll('script, style, noscript, [hidden], nav, header, footer').forEach(e => e.remove());
            const text = clone.innerText.replace(/\\s+/g, ' ').trim();
            
            const links = Array.from(document.querySelectorAll('a')).map(a => ({
                text: a.innerText.trim().replace(/\\s+/g, ' '),
                href: a.href
            })).filter(l => l.href && !l.href.startsWith('javascript:'));
            
            const scripts = Array.from(document.querySelectorAll('script')).map(s => ({
                src: s.src || '',
                type: s.type || ''
            }));
            
            const metadata = {};
            Array.from(document.querySelectorAll('meta')).forEach(m => {
                const key = m.getAttribute('name') || m.getAttribute('property');
                const val = m.getAttribute('content');
                if (key && val) metadata[key] = val;
            });
            
            return {
                title: document.title,
                text: text,
                links: links,
                scripts: scripts,
                metadata: metadata
            };
        })()
    """
}

// MARK: - WebFetcher Actor

@MainActor
class WebFetcher: NSObject, WKNavigationDelegate {
    private let config: FetchConfig
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<PageResult, Error>?
    
    init(config: FetchConfig) {
        self.config = config
        super.init()
    }
    
    func fetch() async throws -> PageResult {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            let configuration = WKWebViewConfiguration()
            let prefs = WKWebpagePreferences()
            prefs.allowsContentJavaScript = true
            configuration.defaultWebpagePreferences = prefs
            
            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 1024), configuration: configuration)
            self.webView = wv
            wv.navigationDelegate = self
            wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
            
            wv.load(URLRequest(url: config.url))
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task {
            if config.waitTime > 0 {
                try? await Task.sleep(nanoseconds: UInt64(config.waitTime * 1_000_000_000))
            }
            
            do {
                let result = try await extractContent(from: webView)
                continuation?.resume(returning: result)
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
            self.webView = nil
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
    
    private func extractContent(from webView: WKWebView) async throws -> PageResult {
        let title = try await webView.evaluateJavaScript("document.title") as? String ?? ""
        let url = webView.url?.absoluteString ?? config.url.absoluteString
        
        // Custom script execution
        if let script = config.customScript {
            let result = try await webView.evaluateJavaScript(script)
            let resultStr = "\(result)"
            return PageResult(title: title, url: url, content: resultStr, links: nil, scripts: nil, metadata: nil)
        }
        
        switch config.mode {
        case .html:
            let html = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String ?? ""
            return PageResult(title: title, url: url, content: html, links: nil, scripts: nil, metadata: nil)
            
        case .text:
            let text = try await webView.evaluateJavaScript(Scripts.extractText) as? String ?? ""
            return PageResult(title: title, url: url, content: text, links: nil, scripts: nil, metadata: nil)
            
        case .links:
            let linksData = try await webView.evaluateJavaScript(Scripts.extractLinks)
            let linksJSON = try JSONSerialization.data(withJSONObject: linksData ?? [], options: [])
            let links = try JSONDecoder().decode([LinkInfo].self, from: linksJSON)
            return PageResult(title: title, url: url, content: "", links: links, scripts: nil, metadata: nil)
            
        case .scripts:
            let scriptsData = try await webView.evaluateJavaScript(Scripts.extractScripts)
            let scriptsJSON = try JSONSerialization.data(withJSONObject: scriptsData ?? [], options: [])
            let scripts = try JSONDecoder().decode([ScriptInfo].self, from: scriptsJSON)
            return PageResult(title: title, url: url, content: "", links: nil, scripts: scripts, metadata: nil)
            
        case .json:
            let allData = try await webView.evaluateJavaScript(Scripts.extractAllJSON)
            guard let dict = allData as? [String: Any] else {
                throw URLError(.cannotDecodeRawData)
            }
            
            let text = dict["text"] as? String ?? ""
            var links: [LinkInfo] = []
            if let linkArr = dict["links"] as? [[String: Any]] {
                for l in linkArr {
                    if let t = l["text"] as? String, let h = l["href"] as? String {
                        links.append(LinkInfo(text: t, href: h))
                    }
                }
            }
            
            var scripts: [ScriptInfo] = []
            if let scriptArr = dict["scripts"] as? [[String: Any]] {
                for s in scriptArr {
                    if let src = s["src"] as? String, let type = s["type"] as? String {
                        scripts.append(ScriptInfo(src: src, type: type))
                    }
                }
            }
            
            let metadata = dict["metadata"] as? [String: String]
            return PageResult(title: title, url: url, content: text, links: links, scripts: scripts, metadata: metadata)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    let config: FetchConfig
    
    init(config: FetchConfig) {
        self.config = config
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            Task {
                try? await Task.sleep(nanoseconds: UInt64(config.timeout * 1_000_000_000))
                fputs("Error: Operation timed out\n", stderr)
                exit(1)
            }
            
            let fetcher = WebFetcher(config: config)
            do {
                let result = try await fetcher.fetch()
                printOutput(result, mode: config.mode)
                exit(0)
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
    }
    
    func printOutput(_ result: PageResult, mode: OutputMode) {
        switch mode {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(result), let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        case .links:
            result.links?.forEach { print("\($0.text) -> \($0.href)") }
        case .scripts:
            result.scripts?.forEach { print("[\($0.type)] \($0.src)") }
        case .text, .html:
            print(result.content)
        }
    }
}

// MARK: - CLI Parsing

func parseArgs() -> FetchConfig {
    var args = Array(CommandLine.arguments.dropFirst())
    var urlString: String?
    var waitTime: TimeInterval = 0
    var timeout: TimeInterval = 30
    var mode: OutputMode = .html
    var customScript: String?
    
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--wait":
            if !args.isEmpty, let val = Double(args.removeFirst()) { waitTime = val }
        case "--timeout":
            if !args.isEmpty, let val = Double(args.removeFirst()) { timeout = val }
        case "--mode":
            if !args.isEmpty, let val = OutputMode(rawValue: args.removeFirst()) { mode = val }
        case "--script":
            if !args.isEmpty { customScript = args.removeFirst() }
        default:
            if !arg.hasPrefix("-") { urlString = arg }
        }
    }
    
    guard let str = urlString, let url = URL(string: str) else {
        print("Usage: swiftfejs <URL> [--wait <sec>] [--timeout <sec>] [--mode html|text|json|links|scripts] [--script <js>]")
        exit(1)
    }
    
    return FetchConfig(url: url, waitTime: waitTime, timeout: timeout, mode: mode, customScript: customScript)
}

// MARK: - Entry Point

@main
struct SwiftFejsTool {
    static func main() {
        let config = parseArgs()
        let app = NSApplication.shared
        let delegate = AppDelegate(config: config)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
