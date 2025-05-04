import Foundation

class YouTubeAPI {
    private let auth: YouTubeAuth
    private let baseURL = "https://www.googleapis.com/youtube/v3"

    init(auth: YouTubeAuth) {
        self.auth = auth
    }

    private func performRequest(endpoint: String, parameters: [String: String], completion: @escaping (Data?) -> Void) {
        auth.ensureValidToken { [weak self] success in
            guard success, let self = self, let accessToken = self.auth.accessToken else {
                completion(nil)
                return
            }

            var components = URLComponents(string: "\(self.baseURL)/\(endpoint)")!
            components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { data, _, _ in
                completion(data)
            }.resume()
        }
    }

    func getActiveLiveVideoId(channelId: String, completion: @escaping (String?) -> Void) {
        performRequest(endpoint: "search", parameters: [
            "part": "snippet",
            "channelId": channelId,
            "eventType": "live",
            "type": "video"
        ]) { data in
            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let items = json["items"] as? [[String: Any]],
                let id = items.first?["id"] as? [String: Any],
                let videoId = id["videoId"] as? String
            else {
                completion(nil)
                return
            }

            completion(videoId)
        }
    }

    func getLiveChatId(videoId: String, completion: @escaping (String?) -> Void) {
        performRequest(endpoint: "videos", parameters: [
            "part": "liveStreamingDetails",
            "id": videoId
        ]) { data in
            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let items = json["items"] as? [[String: Any]],
                let details = items.first?["liveStreamingDetails"] as? [String: Any],
                let liveChatId = details["activeLiveChatId"] as? String
            else {
                completion(nil)
                return
            }

            completion(liveChatId)
        }
    }
}
