//
//  CatalogRepositories.swift
//  iptv
//
//  Created by Codex on 13.03.26.
//

import Foundation

@MainActor
protocol CategoryRepository: AnyObject {
    func loadCategories(for contentType: XtreamContentType, policy: CatalogLoadPolicy) async throws
    func categories(for contentType: XtreamContentType) -> [Category]
}

@MainActor
protocol StreamRepository: AnyObject {
    func loadStreams(in category: Category, contentType: XtreamContentType, policy: CatalogLoadPolicy) async throws
    func videos(in category: Category, contentType: XtreamContentType) -> [Video]
}

extension Catalog: CategoryRepository {
    func loadCategories(for contentType: XtreamContentType, policy: CatalogLoadPolicy) async throws {
        try await getCategories(for: contentType, policy: policy)
    }
}

extension Catalog: StreamRepository {
    func loadStreams(in category: Category, contentType: XtreamContentType, policy: CatalogLoadPolicy) async throws {
        try await getStreams(in: category, contentType: contentType, policy: policy)
    }

    func videos(in category: Category, contentType: XtreamContentType) -> [Video] {
        cachedVideos(in: category, contentType: contentType) ?? []
    }
}
