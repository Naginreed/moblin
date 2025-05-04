import Foundation

class YouTubeLiveChat {
    private let api: YouTubeAPI
    private var liveChatId: String?
    private var pollingTimer: Timer?
    private var nextPageToken: String?
    private let pollInterval: TimeInterval = 5.0
    var onMessageReceived: (([String]) -> Void)?

    init(api: YouTubeAPI, channelId: String) {
        self.api = api

        // Discover current livestream and get chat ID
        api.getActiveLiveVideoId(channelId: channelId) { [weak self] videoId in
            guard let self = self, let videoId = videoId else {
                print("No active livestream found.")
                return
            }

            self.api.getLiveChatId(videoId: videoId) { chatId in
                guard let chatId = chatId else {
                    print("Failed to get liveChatId.")
                    return
                }

                self.liveChatId = chatId
                self.startPolling()
            }
        }
    }

    private func startPolling() {
        DispatchQueue.main.async {
            self.pollingTimer = Timer.scheduledTimer(withTimeInterval: self.pollInterval, repeats: true) { _ in
                self.pollChat()
            }
        }
    }

    private func pollChat() {
        guard let liveChatId = liveChatId else { return }

        var params: [String: String] = [
            "part": "snippet",
            "liveChatId": liveChatId,
        ]
        if let token = nextPageToken {
            params["pageToken"] = token
        }

        api.performRequest(endpoint: "liveChat/messages", parameters: params) { [weak self] data in
            guard
                let self = self,
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let items = json["items"] as? [[String: Any]]
            else {
                return
            }

            self.nextPageToken = json["nextPageToken"] as? String

            let messages: [String] = items.compactMap {
                if
                    let snippet = $0["snippet"] as? [String: Any],
                    let displayMessage = snippet["displayMessage"] as? String
                {
                    return displayMessage
                }
                return nil
            }

            if !messages.isEmpty {
                DispatchQueue.main.async {
                    self.onMessageReceived?(messages)
                }
            }
        }
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
}
