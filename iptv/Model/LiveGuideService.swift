import Foundation

struct LiveGuideProgramme: Identifiable, Sendable {
    let id: String
    let title: String
    let description: String?
    let start: Date
    let end: Date
    let archiveAvailable: Bool
    let catchupStartComponent: String
}

struct LiveGuideService {
    func programmes(for channel: Media, provider: ProviderConfiguration) async throws -> [LiveGuideProgramme] {
        guard var components = URLComponents(url: provider.endpoint, resolvingAgainstBaseURL: false) else {
            throw GuideError.invalidEndpoint
        }
        components.queryItems = [
            URLQueryItem(name: "username", value: provider.username),
            URLQueryItem(name: "password", value: provider.password),
            URLQueryItem(name: "action", value: "get_short_epg"),
            URLQueryItem(name: "stream_id", value: String(channel.sourceID)),
            URLQueryItem(name: "limit", value: "12"),
        ]
        guard let url = components.url else { throw GuideError.invalidEndpoint }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let response = response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            throw GuideError.httpStatus(response.statusCode)
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.epgListings.compactMap(\.programme).sorted { $0.start < $1.start }
    }

    func catchupURL(
        for programme: LiveGuideProgramme,
        channel: Media,
        provider: ProviderConfiguration
    ) throws -> URL {
        guard channel.supportsCatchup, programme.archiveAvailable else {
            throw GuideError.catchupUnavailable
        }
        let duration = max(Int(ceil(programme.end.timeIntervalSince(programme.start) / 60)), 1)
        let baseURL = provider.endpoint.deletingLastPathComponent()
        let components = [
            "timeshift",
            provider.username,
            provider.password,
            String(duration),
            programme.catchupStartComponent,
            "\(channel.sourceID).ts",
        ]
        return components.reduce(baseURL) { url, component in
            url.appendingPathComponent(component)
        }
    }

    private struct Payload: Decodable {
        let epgListings: [Listing]

        enum CodingKeys: String, CodingKey { case epgListings = "epg_listings" }
    }

    private struct Listing: Decodable {
        let id: String?
        let title: String?
        let description: String?
        let start: String?
        let end: String?
        let startTimestamp: String?
        let stopTimestamp: String?
        let hasArchive: Int?

        enum CodingKeys: String, CodingKey {
            case id, title, description, start, end
            case startTimestamp = "start_timestamp"
            case stopTimestamp = "stop_timestamp"
            case hasArchive = "has_archive"
        }

        var programme: LiveGuideProgramme? {
            guard let startDate = Self.date(timestamp: startTimestamp, text: start),
                  let endDate = Self.date(timestamp: stopTimestamp, text: end),
                  endDate > startDate
            else { return nil }
            return LiveGuideProgramme(
                id: id ?? "\(startDate.timeIntervalSince1970)",
                title: Self.decoded(title) ?? "Untitled programme",
                description: Self.decoded(description),
                start: startDate,
                end: endDate,
                archiveAvailable: hasArchive == 1,
                catchupStartComponent: Self.catchupFormatter.string(from: startDate)
            )
        }

        private static func decoded(_ value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            if let data = Data(base64Encoded: value),
               let decoded = String(data: data, encoding: .utf8),
               !decoded.isEmpty {
                return decoded
            }
            return value
        }

        private static func date(timestamp: String?, text: String?) -> Date? {
            if let timestamp, let seconds = TimeInterval(timestamp) {
                return Date(timeIntervalSince1970: seconds)
            }
            guard let text else { return nil }
            return sourceFormatter.date(from: text)
        }

        private static let sourceFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter
        }()

        private static let catchupFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd:HH-mm"
            return formatter
        }()
    }

    enum GuideError: LocalizedError {
        case invalidEndpoint
        case httpStatus(Int)
        case catchupUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: "The provider guide endpoint is invalid."
            case .httpStatus(let status): "The provider guide returned HTTP \(status)."
            case .catchupUnavailable: "Catch-up is not available for this programme."
            }
        }
    }
}
