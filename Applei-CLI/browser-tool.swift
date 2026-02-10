import WebKit
import Foundation
import AppKit
import Observation

// MARK: - Observable Browser State

@Observable
class BrowserState {
    var isLoading: Bool = false
    var currentURL: String = ""
    var pageTitle: String = ""
    var interactiveElements: [InteractiveElement] = []
    var error: String?
}

struct InteractiveElement: Identifiable, Codable {
    let id: Int
    let type: String
    let text: String
    let selector: String
    let bounds: CGRect?
}

// MARK: - Browser Automation Tool

@MainActor
class BrowserAutomation: NSObject, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView?
    private var state = BrowserState()
    private var continuation: CheckedContinuation<String, Error>?
    
    // Execute browser action
    func execute(url: String, action: BrowserAction) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            let config = WKWebViewConfiguration()
            config.defaultWebpagePreferences.allowsContentJavaScript = true
            
            // Enable modern WebKit features
            config.preferences.setValue(true, forKey: "developerExtrasEnabled")
            
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 1024), configuration: config)
            self.webView = webView
            webView.navigationDelegate = self
            webView.uiDelegate = self
            
            state.isLoading = true
            
            if let url = URL(string: url) {
                webView.load(URLRequest(url: url))
            }
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task {
            state.isLoading = false
            state.currentURL = webView.url?.absoluteString ?? ""
            if let title = try? await webView.evaluateJavaScript("document.title") as? String {
                state.pageTitle = title
            }
            
            // Wait for dynamic content
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            // Extract interactive elements
            await extractInteractiveElements(from: webView)
            
            // Return numbered list
            let result = formatElementList(state.interactiveElements)
            continuation?.resume(returning: result)
            continuation = nil
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        state.error = error.localizedDescription
        continuation?.resume(throwing: error)
        continuation = nil
    }
    
    // MARK: - Element Extraction
    
    private func extractInteractiveElements(from webView: WKWebView) async {
        let script = """
        (function() {
            const elements = [];
            const selectors = 'a, button, input, textarea, select, [role="button"], [onclick], [tabindex]';
            
            document.querySelectorAll(selectors).forEach((el, index) => {
                const rect = el.getBoundingClientRect();
                const isVisible = rect.width > 0 && rect.height > 0 && 
                                 window.getComputedStyle(el).visibility !== 'hidden' &&
                                 window.getComputedStyle(el).display !== 'none';
                
                if (isVisible) {
                    elements.push({
                        id: index + 1,
                        type: el.tagName.toLowerCase(),
                        text: (el.innerText || el.value || el.placeholder || el.getAttribute('aria-label') || '').trim().substring(0, 60),
                        selector: generateSelector(el),
                        bounds: {
                            x: rect.x,
                            y: rect.y,
                            width: rect.width,
                            height: rect.height
                        }
                    });
                }
            });
            
            function generateSelector(el) {
                if (el.id) return '#' + el.id;
                if (el.className) return el.tagName.toLowerCase() + '.' + el.className.split(' ')[0];
                return el.tagName.toLowerCase();
            }
            
            return elements;
        })()
        """
        
        do {
            if let result = try await webView.evaluateJavaScript(script) as? [[String: Any]] {
                state.interactiveElements = result.compactMap { dict in
                    guard let id = dict["id"] as? Int,
                          let type = dict["type"] as? String,
                          let text = dict["text"] as? String,
                          let selector = dict["selector"] as? String else {
                        return nil
                    }
                    
                    var bounds: CGRect?
                    if let boundsDict = dict["bounds"] as? [String: Double] {
                        bounds = CGRect(
                            x: boundsDict["x"] ?? 0,
                            y: boundsDict["y"] ?? 0,
                            width: boundsDict["width"] ?? 0,
                            height: boundsDict["height"] ?? 0
                        )
                    }
                    
                    return InteractiveElement(
                        id: id,
                        type: type,
                        text: text,
                        selector: selector,
                        bounds: bounds
                    )
                }
            }
        } catch {
            state.error = "Failed to extract elements: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Element Interaction
    
    func clickElement(number: Int) async throws -> String {
        guard let webView = webView else {
            throw NSError(domain: "BrowserAutomation", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebView not initialized"])
        }
        
        let script = """
        (function() {
            const selectors = 'a, button, input, textarea, select, [role="button"], [onclick], [tabindex]';
            const elements = Array.from(document.querySelectorAll(selectors)).filter(el => {
                const rect = el.getBoundingClientRect();
                return rect.width > 0 && rect.height > 0;
            });
            
            if (elements[\(number - 1)]) {
                elements[\(number - 1)].click();
                return 'Clicked: ' + (elements[\(number - 1)].innerText || elements[\(number - 1)].tagName).substring(0, 50);
            }
            return 'Element not found';
        })()
        """
        
        let result = try await webView.evaluateJavaScript(script)
        return result as? String ?? "Action completed"
    }
    
    func typeText(number: Int, text: String) async throws -> String {
        guard let webView = webView else {
            throw NSError(domain: "BrowserAutomation", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebView not initialized"])
        }
        
        let escapedText = text.replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (function() {
            const selectors = 'input, textarea';
            const elements = Array.from(document.querySelectorAll(selectors)).filter(el => {
                const rect = el.getBoundingClientRect();
                return rect.width > 0 && rect.height > 0;
            });
            
            if (elements[\(number - 1)]) {
                elements[\(number - 1)].value = '\(escapedText)';
                elements[\(number - 1)].dispatchEvent(new Event('input', { bubbles: true }));
                elements[\(number - 1)].dispatchEvent(new Event('change', { bubbles: true }));
                return 'Typed into: ' + (elements[\(number - 1)].placeholder || elements[\(number - 1)].name || 'input');
            }
            return 'Element not found';
        })()
        """
        
        let result = try await webView.evaluateJavaScript(script)
        return result as? String ?? "Text entered"
    }
    
    func extractText(selector: String) async throws -> String {
        guard let webView = webView else {
            throw NSError(domain: "BrowserAutomation", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebView not initialized"])
        }
        
        let script = """
        (function() {
            const el = document.querySelector('\(selector)');
            return el ? el.innerText : 'Element not found';
        })()
        """
        
        let result = try await webView.evaluateJavaScript(script)
        return result as? String ?? ""
    }
    
    // MARK: - Formatting
    
    private func formatElementList(_ elements: [InteractiveElement]) -> String {
        var output = "Interactive Elements:\n\n"
        for element in elements.prefix(50) { // Limit to 50 to avoid context overflow
            output += "\(element.id). [\(element.type.uppercased())] \(element.text)\n"
        }
        if elements.count > 50 {
            output += "\n... and \(elements.count - 50) more elements"
        }
        return output
    }
}

// MARK: - Browser Action Types

enum BrowserAction {
    case list
    case click(Int)
    case type(Int, String)
    case extract(String)
}

// MARK: - CLI Entry Point

@main
struct BrowserTool {
    static func main() async {
        let args = CommandLine.arguments.dropFirst()
        
        guard args.count >= 2 else {
            print("Usage: browser-tool <url> <action>")
            print("Actions:")
            print("  list                    - List all interactive elements")
            print("  click <number>          - Click element by number")
            print("  type <number> <text>    - Type text into input")
            print("  extract <selector>      - Extract text from element")
            exit(1)
        }
        
        let url = String(args.first!)
        let actionStr = String(args.dropFirst().first!)
        
        let action: BrowserAction
        if actionStr == "list" {
            action = .list
        } else if actionStr == "click", let num = Int(args.dropFirst(2).first ?? "") {
            action = .click(num)
        } else if actionStr == "type", let num = Int(args.dropFirst(2).first ?? ""), args.count >= 4 {
            let text = args.dropFirst(3).joined(separator: " ")
            action = .type(num, text)
        } else if actionStr == "extract", let selector = args.dropFirst(2).first {
            action = .extract(String(selector))
        } else {
            print("Invalid action")
            exit(1)
        }
        
        let automation = BrowserAutomation()
        
        do {
            let result = try await automation.execute(url: url, action: action)
            print(result)
            exit(0)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
