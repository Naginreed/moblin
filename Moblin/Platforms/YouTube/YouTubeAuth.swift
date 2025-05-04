import SwiftUI
import WebKit
import Security

private let youtubeServer = "accounts.google.com"
private let authorizeUrl = "https://accounts.google.com/o/oauth2/v2/auth"
private let tokenUrl = "https://oauth2.googleapis.com/token"
private let clientId = "YOUR_CLIENT_ID"
private let clientSecret = "YOUR_CLIENT_SECRET"
private let redirectHost = "localhost"
private let redirectUri = "https://\(redirectHost)"
private let scopes = [
    "https://www.googleapis.com/auth/youtube.readonly"
]

struct YouTubeAuthView: UIViewRepresentable {
    let youtubeAuth: YouTubeAuth

    func makeUIView(context _: Context) -> WKWebView {
        return youtubeAuth.getWebBrowser()
    }

    func updateUIView(_: WKWebView, context _: Context) {}
}

class YouTubeAuth: NSObject {
    private var webBrowser: WKWebView?
    private var onAccessToken: ((String) -> Void)?

    func getWebBrowser() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        webBrowser = WKWebView(frame: .zero, configuration: configuration)
        webBrowser!.navigationDelegate = self
        webBrowser!.load(URLRequest(url: buildAuthUrl()!))
        return webBrowser!
    }

    func setOnAccessToken(onAccessToken: @escaping ((String) -> Void)) {
        self.onAccessToken = onAccessToken
    }

    private func buildAuthUrl() -> URL? {
        guard var urlComponents = URLComponents(string: authorizeUrl) else { return nil }
        urlComponents.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: redirectUri),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]
        return urlComponents.url
    }

    private func exchangeCodeForToken(code: String) {
        var request = URLRequest(url: URL(string: tokenUrl)!)
        request.httpMethod = "POST"
        let params = [
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirectUri,
            "grant_type": "authorization_code"
        ]
        request.httpBody = params
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard
                let data = data,
                error == nil,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let accessToken = json["access_token"] as? String
            else {
                return
            }

            self.storeYouTubeAccessTokenInKeychain(accessToken: accessToken)
            self.onAccessToken?(accessToken)
        }.resume()
    }

    private func updateAccessTokenInKeychain(accessTokenData: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: youtubeServer,
            kSecAttrAccount as String: "youtube_access_token"
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: accessTokenData
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status != errSecItemNotFound else { return false }
        guard status == errSecSuccess else {
            print("youtube: auth: Failed to update item in keychain")
            return false
        }
        return true
    }

    private func addAccessTokenInKeychain(accessTokenData: Data) {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: youtubeServer,
            kSecAttrAccount as String: "youtube_access_token",
            kSecValueData as String: accessTokenData
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            print("youtube: auth: Failed to add item to keychain")
            return
        }
    }

    func storeYouTubeAccessTokenInKeychain(accessToken: String) {
        guard let accessTokenData = accessToken.data(using: .utf8) else { return }
        if !updateAccessTokenInKeychain(accessTokenData: accessTokenData) {
            addAccessTokenInKeychain(accessTokenData: accessTokenData)
        }
    }

    func loadYouTubeAccessTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: youtubeServer,
            kSecAttrAccount as String: "youtube_access_token",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else {
            print("youtube: auth: Failed to query item from keychain")
            return nil
        }
        guard
            let existingItem = item as? [String: Any],
            let accessTokenData = existingItem[kSecValueData as String] as? Data,
            let accessToken = String(data: accessTokenData, encoding: .utf8)
        else {
            print("youtube: auth: Failed to extract access token")
            return nil
        }
        return accessToken
    }

    func removeYouTubeAccessTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: youtubeServer,
            kSecAttrAccount as String: "youtube_access_token"
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            print("youtube: auth: Failed to delete item from keychain")
            return
        }
    }
}

extension YouTubeAuth: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        guard let url = webView.url else { return }
        guard url.host == redirectHost else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else { return }
        exchangeCodeForToken(code: code)
    }
}
