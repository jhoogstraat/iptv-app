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
        self.baseURL = baseURL
        self.username = username
        self.password = password
    }

    var auth: [URLQueryItem] { [.init(name: "username", value: username), .init(name: "password", value: password)] }

    func getCategories(of type: XtreamContentType) async throws -> [XtreamCategory] {
        let query = [URLQueryItem(name: "action", value: "get_\(type)_categories")]
        let resource = Resource<[XtreamCategory]>(url: baseURL, method: .get(auth + query))
        let data = try await client.load(resource)
        return data
    }
    
    func getStreams(of type: XtreamContentType, in category: String? = nil) async throws -> [XtreamStream] {
        let action = type == .series ? "get_\(type)" : "get_\(type)_streams"
        let query = [URLQueryItem(name: "action", value: action), URLQueryItem(name: "category_id", value: category)]
        let resource = Resource<[XtreamStream]>(url: baseURL, method: .get(auth + query))
        let data = try await client.load(resource)
        return data
    }

    func getSeries(in category: String? = nil) async throws -> [XtreamSeriesStream] {
        let query = [URLQueryItem(name: "action", value: "get_series"), URLQueryItem(name: "category_id", value: category)]
        let resource = Resource<[XtreamSeriesStream]>(url: baseURL, method: .get(auth + query))
        let data = try await client.load(resource)
        return data
    }
    
    func getVodInfo(of id: String) async throws -> XtreamVod {
        let query = [URLQueryItem(name: "action", value: "get_vod_info"), URLQueryItem(name: "vod_id", value: id)]
        let resource = Resource<XtreamVod>(url: baseURL, method: .get(auth + query))
        let data = try await client.load(resource)
        return data
    }
    
    func getPlayURL(for streamId: Int, type: String, containerExtension: String) -> URL {
        let url = URL(string: "\(type)/\(username)/\(password)/\(streamId).\(containerExtension)", relativeTo: baseURL)!
        return url
    }
}
