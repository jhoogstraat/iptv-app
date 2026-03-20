//
//  Service.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 02.09.25.
//

import Foundation
import os

struct XtreamService: Sendable {
    let client: HTTPClient
    
    let baseURL: URL
    let username: String
    let password: String
    
    init(_ client: HTTPClient, baseURL: URL, username: String, password: String) {
        self.client = client
        self.baseURL = baseURL.appendingPathComponent("player_api.php")
        self.username = username
        self.password = password
    }

    var auth: [URLQueryItem] { [.init(name: "username", value: username), .init(name: "password", value: password)] }

    func getCategories(of type: Xtream.ContentType) async throws -> [Xtream.Category] {
        let query = [URLQueryItem(name: "action", value: "get_\(type)_categories")]
        let resource = Resource<[Xtream.Category]>(url: baseURL, method: .get(auth + query))
        let data = try await client.load(resource)
        return data
    }
    
    func getStreams(of type: Xtream.ContentType, in category: String? = nil) async throws -> [Xtream.MovieStream] {
        let action = type == .series ? "get_\(type)" : "get_\(type)_streams"
        let query = [URLQueryItem(name: "action", value: action), URLQueryItem(name: "category_id", value: category)]
        let resource = Resource<[Xtream.MovieStream]>(url: baseURL, method: .get(auth + query))
        let data = try await client.load(resource)
        return data
    }

    func getVodInfo(of id: Int) async throws -> Xtream.Movie {
        let query = [URLQueryItem(name: "action", value: "get_vod_info"), URLQueryItem(name: "vod_id", value: "\(id)")]
        let resource = Resource<Xtream.Movie>(url: baseURL, method: .get(auth + query))
        let data = try await client.load(resource)
        return data
    }
    
    func getSeries(in category: String? = nil) async throws -> [Xtream.SeriesStream] {
        let query = [URLQueryItem(name: "action", value: "get_series"), URLQueryItem(name: "category_id", value: category)]
        let resource = Resource<[Xtream.SeriesStream]>(url: baseURL, method: .get(auth + query))
        let data = try await client.load(resource)
        return data
    }

    func getSeriesInfo(of id: String) async throws -> Xtream.Series {
        let query = [URLQueryItem(name: "action", value: "get_series_info"), URLQueryItem(name: "series_id", value: id)]
        let resource = Resource<Xtream.Series>(url: baseURL, method: .get(auth + query))
        let data = try await client.load(resource)
        return data
    }
    
    func getPlayURL(for streamId: Int, type: Xtream.ContentType, containerExtension: String?) -> URL {
        let url = URL(string: "\(type.playbackPathComponent)/\(username)/\(password)/\(streamId)" + (containerExtension != nil ? ".\(containerExtension!)" : ""), relativeTo: baseURL)!
        return url
    }
}
