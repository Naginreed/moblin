import Foundation

class YouTubeEvents {
    private let api: YouTubeAPI
    private var liveChatId: String?
    private var pollingTimer: Timer?
    private var nextPageToken: String?
    private let pollInterval: TimeInterval = 5.0

    var onSuperChat: ((String, String, Double) -> Void)?
    var onNewMember: ((String) -> Void)?

    init(api: YouTubeAPI, channelId: String) {
        self.api = api

        // Get livestream video ID and chat ID
        api.getActiveLiveVideoId(channelId: channelId) { [weak self] videoId in
            guard let self = self, let videoId = videoId else { return }

            self.api.getLiveChatId(videoId: videoId) { chatId in
                guard let chatId = chatId else { return }

                self.liveChatId = chatId
                self.startPolling()
            }
        }
    }

    private func startPolling() {
        DispatchQueue.main.async {
            self.pollingTimer = Timer.scheduledTimer(withTimeInterval: self.pollInterval, repeats: true) { _ in
                self.pollChatForEvents()
            }
        }
    }

    private func pollChatForEvents() {
        guard let liveChatId = liveChatId else { return }

        var params: [String: String] = [
            "part": "snippet,authorDetails",
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

            for item in items {
                guard let snippet = item["snippet"] as? [String: Any],
                      let type = snippet["type"] as? String,
                      let author = item["authorDetails"] as? [String: Any],
                      let displayName = author["displayName"] as? String else { continue }

                switch type {
                case "superChatEvent":
                    if let amountMicros = snippet["superChatDetails"] as? [String: Any],
                       let amount = amountMicros["amountMicros"] as? Double,
                       let currency = amountMicros["currency"] as? String {
                        self.onSuperChat?(displayName, currency, amount / 1_000_000.0)
                    }
                case "newSponsorEvent":
                    self.onNewMember?(displayName)
                default:
                    break
                }
            }
        }
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
}
