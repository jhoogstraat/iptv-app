//
//  ImageCache.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import Foundation

enum SharedImageURLCache {
    static func configureIfNeeded(
        memoryCapacity: Int = 96 * 1024 * 1024,
        diskCapacity: Int = 512 * 1024 * 1024
    ) {
        let current = URLCache.shared
        let targetMemory = max(current.memoryCapacity, memoryCapacity)
        let targetDisk = max(current.diskCapacity, diskCapacity)

        guard targetMemory != current.memoryCapacity || targetDisk != current.diskCapacity else { return }

        URLCache.shared = URLCache(
            memoryCapacity: targetMemory,
            diskCapacity: targetDisk,
            diskPath: "ImageURLCache"
        )
    }
}

actor URLSessionImagePrefetcher: ImagePrefetching {
    typealias Fetcher = @Sendable (URL) async throws -> (Data, HTTPURLResponse)

    private let cache: URLCache
    private let fetcher: Fetcher
    private let maxAge: TimeInterval
    private let maxConcurrentPrefetches: Int
    private var inFlight: [URL: Task<Void, Never>] = [:]

    init(
        cache: URLCache = .shared,
        maxAge: TimeInterval = 12 * 60 * 60,
        maxConcurrentPrefetches: Int = 6,
        fetcher: @escaping Fetcher = URLSessionImagePrefetcher.liveFetcher
    ) {
        self.cache = cache
        self.fetcher = fetcher
        self.maxAge = maxAge
        self.maxConcurrentPrefetches = max(1, maxConcurrentPrefetches)
    }

    func prefetch(urls: [URL]) async {
        let targets = uniqueHTTPURLs(from: urls)
        guard !targets.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var iterator = targets.makeIterator()
            let initial = min(maxConcurrentPrefetches, targets.count)

            for _ in 0..<initial {
                guard let next = iterator.next() else { break }
                group.addTask {
                    await self.prefetchOne(next)
                }
            }

            while await group.next() != nil {
                guard let next = iterator.next() else { continue }
                group.addTask {
                    await self.prefetchOne(next)
                }
            }
        }
    }

    private func prefetchOne(_ url: URL) async {
        let request = cacheRequest(for: url)

        guard cache.cachedResponse(for: request) == nil else { return }

        if let existing = inFlight[url] {
            await existing.value
            return
        }

        let task = Task(priority: .utility) { [cache, fetcher, maxAge] in
            do {
                let (data, response) = try await fetcher(url)
                guard !data.isEmpty, (200..<300).contains(response.statusCode) else { return }

                let cacheableResponse = URLSessionImagePrefetcher.makeCacheableResponse(from: response, maxAge: maxAge)
                let cached = CachedURLResponse(response: cacheableResponse, data: data, storagePolicy: .allowed)
                cache.storeCachedResponse(cached, for: request)
            } catch {
                return
            }
        }

        inFlight[url] = task
        await task.value
        inFlight[url] = nil
    }

    private func cacheRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .useProtocolCachePolicy
        return request
    }

    private func uniqueHTTPURLs(from urls: [URL]) -> [URL] {
        var seen: Set<URL> = []
        var unique: [URL] = []
        unique.reserveCapacity(urls.count)

        for url in urls {
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { continue }
            if seen.insert(url).inserted {
                unique.append(url)
            }
        }

        return unique
    }

    nonisolated private static func makeCacheableResponse(from response: HTTPURLResponse, maxAge: TimeInterval) -> HTTPURLResponse {
        let ttl = max(60, Int(maxAge.rounded()))
        var headerFields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let keyString = key as? String else { continue }
            headerFields[keyString] = String(describing: value)
        }
        headerFields["Cache-Control"] = "public, max-age=\(ttl)"

        guard let url = response.url else { return response }

        return HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        ) ?? response
    }

    nonisolated private static func liveFetcher(url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        return (data, httpResponse)
    }
}
