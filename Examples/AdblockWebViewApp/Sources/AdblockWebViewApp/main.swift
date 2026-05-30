import AdblockRust
import AppKit
import Foundation
import WebKit

private enum FilterListSource: String, CaseIterable {
  case easyList = "https://easylist.to/easylist/easylist.txt"
  case easyPrivacy = "https://easylist.to/easylist/easyprivacy.txt"

  var url: URL {
    URL(string: rawValue)!
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
  private var window: NSWindow!
  private var webView: WKWebView!
  private let addressField = NSTextField(string: "https://example.com")
  private let statusLabel = NSTextField(labelWithString: "Preparing ad blocker...")

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    buildWindow()

    Task { @MainActor in
      await installContentBlocker()
      loadCurrentAddress()
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  private func buildWindow() {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()

    webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = self

    let toolbar = NSStackView()
    toolbar.orientation = .horizontal
    toolbar.alignment = .centerY
    toolbar.spacing = 8
    toolbar.translatesAutoresizingMaskIntoConstraints = false

    let loadButton = NSButton(title: "Load", target: self, action: #selector(loadCurrentAddress))
    let reloadButton = NSButton(title: "Reload", target: self, action: #selector(reloadPage))

    addressField.target = self
    addressField.action = #selector(loadCurrentAddress)
    addressField.placeholderString = "https://example.com"

    toolbar.addArrangedSubview(addressField)
    toolbar.addArrangedSubview(loadButton)
    toolbar.addArrangedSubview(reloadButton)

    addressField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    loadButton.setContentHuggingPriority(.required, for: .horizontal)
    reloadButton.setContentHuggingPriority(.required, for: .horizontal)

    statusLabel.lineBreakMode = .byTruncatingTail
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    webView.translatesAutoresizingMaskIntoConstraints = false

    let contentView = NSView()
    contentView.addSubview(toolbar)
    contentView.addSubview(statusLabel)
    contentView.addSubview(webView)

    NSLayoutConstraint.activate([
      toolbar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
      toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
      toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),

      statusLabel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
      statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
      statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),

      webView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
      webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Adblock WebView Example"
    window.contentView = contentView
    window.center()
    window.makeKeyAndOrderFront(nil)
  }

  @objc private func loadCurrentAddress() {
    guard var components = URLComponents(string: addressField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      statusLabel.stringValue = "Invalid URL"
      return
    }

    if components.scheme == nil {
      components.scheme = "https"
    }

    guard let url = components.url else {
      statusLabel.stringValue = "Invalid URL"
      return
    }

    addressField.stringValue = url.absoluteString
    webView.load(URLRequest(url: url))
  }

  @objc private func reloadPage() {
    webView.reload()
  }

  @MainActor private func installContentBlocker() async {
    do {
      let rules = try await downloadRules()
      let converted = try AdblockEngine.contentBlockingRules(fromFilterSet: rules)
      let ruleList = try await compileRuleList(json: converted.json)
      webView.configuration.userContentController.add(ruleList)

      let suffix = converted.truncated ? " Rules were truncated to WebKit's limit." : ""
      statusLabel.stringValue = "Ad blocker ready: EasyList + EasyPrivacy.\(suffix)"
    } catch {
      statusLabel.stringValue = "Ad blocker unavailable: \(error.localizedDescription)"
    }
  }

  private func downloadRules() async throws -> String {
    var lists: [String] = []
    for source in FilterListSource.allCases {
      let (data, response) = try await URLSession.shared.data(from: source.url)
      guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
        throw URLError(.badServerResponse)
      }
      guard let text = String(data: data, encoding: .utf8) else {
        throw AdblockRustError.invalidUTF8
      }
      lists.append(text)
    }
    return lists.joined(separator: "\n")
  }

  private func compileRuleList(json: String) async throws -> WKContentRuleList {
    try await withCheckedThrowingContinuation { continuation in
      WKContentRuleListStore.default().compileContentRuleList(
        forIdentifier: "AdblockWebViewApp.EasyListEasyPrivacy",
        encodedContentRuleList: json
      ) { ruleList, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let ruleList else {
          continuation.resume(throwing: CocoaError(.fileNoSuchFile))
          return
        }
        continuation.resume(returning: ruleList)
      }
    }
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    statusLabel.stringValue = "Loading \(webView.url?.absoluteString ?? addressField.stringValue)"
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    statusLabel.stringValue = "Loaded \(webView.url?.absoluteString ?? addressField.stringValue)"
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    statusLabel.stringValue = error.localizedDescription
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
