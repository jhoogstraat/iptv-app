//
//  HTTPClient.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import Foundation

enum NetworkError: Error {
    case badRequest
    case serverError(String)
    case decodingError(Error)
    case invalidResponse
    case invalidURL
    case httpError(Int)
}

extension NetworkError: LocalizedError {
    
    var errorDescription: String? {
        switch self {
            case .badRequest:
                return NSLocalizedString("Unable to perform request", comment: "badRequestError")
            case .serverError(let errorMessage):
                return NSLocalizedString(errorMessage, comment: "serverError")
            case .decodingError:
                return NSLocalizedString("Unable to decode successfully.", comment: "decodingError")
            case .invalidResponse:
                return NSLocalizedString("Invalid response", comment: "invalidResponse")
            case .invalidURL:
                return NSLocalizedString("Invalid URL", comment: "invalidURL")
            case .httpError(_):
                return NSLocalizedString("Bad request", comment: "badRequest")
        }
    }
    
}

enum HTTPMethod {
    case get([URLQueryItem])
    case post(Data?)
    case delete
    
    var name: String {
        switch self {
            case .get:
                return "GET"
            case .post:
                return "POST"
            case .delete:
                return "DELETE"
        }
    }
}

struct Resource<T: Decodable> {
    let url: URL
    var method: HTTPMethod = .get([])
}

struct HTTPClient: Sendable {
    static let shared = HTTPClient()
    private let session: URLSession
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["Content-Type": "application/json"]
        self.session = URLSession(configuration: configuration)
    }
    
    func load<T: Decodable>(_ resource: Resource<T>) async throws -> T {
        var request = URLRequest(url: resource.url)
        request.httpMethod = resource.method.name
        
        switch resource.method {
            case .get(let queryItems):
                let url = resource.url.appending(queryItems: queryItems)
                request = URLRequest(url: url)
                
            case .post(let data):
                request.httpBody = data
                
            case .delete:
                break
        }
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }

        guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(httpResponse.statusCode)
        }
                
        do {
            let result = try JSONDecoder().decode(T.self, from: data)
            return result
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
    
}
