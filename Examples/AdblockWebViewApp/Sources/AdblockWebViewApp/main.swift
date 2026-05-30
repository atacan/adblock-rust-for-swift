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
  private var blockedWebView: WKWebView!
  private var plainWebView: WKWebView!
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
    let blockedConfiguration = WKWebViewConfiguration()
    blockedConfiguration.websiteDataStore = .default()

    let plainConfiguration = WKWebViewConfiguration()
    plainConfiguration.websiteDataStore = .default()

    blockedWebView = WKWebView(frame: .zero, configuration: blockedConfiguration)
    blockedWebView.navigationDelegate = self

    plainWebView = WKWebView(frame: .zero, configuration: plainConfiguration)
    plainWebView.navigationDelegate = self

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

    let comparisonView = NSStackView()
    comparisonView.orientation = .horizontal
    comparisonView.alignment = .height
    comparisonView.distribution = .fillEqually
    comparisonView.spacing = 1
    comparisonView.translatesAutoresizingMaskIntoConstraints = false

    let blockedPane = makeWebViewPane(title: "With ad blocking", webView: blockedWebView)
    let plainPane = makeWebViewPane(title: "Without ad blocking", webView: plainWebView)
    comparisonView.addArrangedSubview(blockedPane)
    comparisonView.addArrangedSubview(plainPane)

    let contentView = NSView()
    contentView.addSubview(toolbar)
    contentView.addSubview(statusLabel)
    contentView.addSubview(comparisonView)

    NSLayoutConstraint.activate([
      toolbar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
      toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
      toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),

      statusLabel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
      statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
      statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),

      comparisonView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
      comparisonView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      comparisonView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      comparisonView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
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

  private func makeWebViewPane(title: String, webView: WKWebView) -> NSView {
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    titleLabel.lineBreakMode = .byTruncatingTail

    webView.translatesAutoresizingMaskIntoConstraints = false

    let pane = NSStackView()
    pane.orientation = .vertical
    pane.alignment = .leading
    pane.spacing = 6
    pane.addArrangedSubview(titleLabel)
    pane.addArrangedSubview(webView)

    titleLabel.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 10).isActive = true
    webView.widthAnchor.constraint(equalTo: pane.widthAnchor).isActive = true
    webView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

    return pane
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
    let request = URLRequest(url: url)
    blockedWebView.load(request)
    plainWebView.load(request)
  }

  @objc private func reloadPage() {
    blockedWebView.reload()
    plainWebView.reload()
  }

  @MainActor private func installContentBlocker() async {
    do {
      let rules = try await downloadRules()
      let converted = try AdblockEngine.contentBlockingRules(fromFilterSet: rules)
      let ruleList = try await compileRuleList(json: converted.json)
      blockedWebView.configuration.userContentController.add(ruleList)

      let suffix = converted.truncated ? " Rules were truncated to WebKit's limit." : ""
      statusLabel.stringValue = "Ad blocker ready on the left pane: EasyList + EasyPrivacy.\(suffix)"
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
    let paneName = webView === blockedWebView ? "left" : "right"
    statusLabel.stringValue = "Loading \(paneName) pane: \(webView.url?.absoluteString ?? addressField.stringValue)"
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    let paneName = webView === blockedWebView ? "left" : "right"
    statusLabel.stringValue = "Loaded \(paneName) pane: \(webView.url?.absoluteString ?? addressField.stringValue)"
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    statusLabel.stringValue = error.localizedDescription
  }
}

private func buildMainMenu() -> NSMenu {
  let mainMenu = NSMenu()
  let appMenuItem = NSMenuItem()
  let appMenu = NSMenu()
  let editMenuItem = NSMenuItem()
  let editMenu = NSMenu(title: "Edit")
  let quitItem = NSMenuItem(
    title: "Quit Adblock WebView Example",
    action: #selector(NSApplication.terminate(_:)),
    keyEquivalent: "q"
  )

  quitItem.target = NSApp
  appMenu.addItem(quitItem)
  appMenuItem.submenu = appMenu
  mainMenu.addItem(appMenuItem)

  editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
  editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
  editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
  editMenu.addItem(NSMenuItem.separator())
  editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
  editMenuItem.submenu = editMenu
  mainMenu.addItem(editMenuItem)

  return mainMenu
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.mainMenu = buildMainMenu()
app.run()
