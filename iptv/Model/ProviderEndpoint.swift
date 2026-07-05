import Foundation

enum ProviderEndpointError: LocalizedError {
    case invalidBaseURL

    var errorDescription: String? {
        "Please enter a valid provider base URL."
    }
}

enum ProviderEndpoint {
    static func normalize(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProviderEndpointError.invalidBaseURL }

        var value = trimmed
        if URLComponents(string: value)?.scheme == nil {
            value = "http://\(value)"
        }

        guard var components = URLComponents(string: value) else {
            throw ProviderEndpointError.invalidBaseURL
        }

        if components.host?.isEmpty ?? true {
            repairPathOnlyHost(in: &components)
        }

        guard let host = components.host,
              !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            throw ProviderEndpointError.invalidBaseURL
        }

        var path = components.path
        if path.isEmpty || path == "/" {
            path = "/player_api.php"
        } else if !path.hasSuffix("/player_api.php") && path != "/player_api.php" {
            path = path.hasSuffix("/") ? "\(path)player_api.php" : "\(path)/player_api.php"
        }
        components.path = path

        guard let url = components.url else {
            throw ProviderEndpointError.invalidBaseURL
        }
        return url
    }

    private static func repairPathOnlyHost(in components: inout URLComponents) {
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return }

        let parts = path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard let host = parts.first else { return }

        components.host = String(host)
        components.path = parts.count > 1 ? "/\(parts[1])" : ""
    }
}
