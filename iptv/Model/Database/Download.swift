//
//  Download.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 16.03.26.
//

import Foundation
import SwiftData

@Model final class Download {
    @Relationship
    var origin: Media
    
    var url: URL
    
    var bytesWritten: Int64
    var expectedBytes: Int64?
    var attempts: Int
    var createdAt: Date
    var updatedAt: Date

    init(origin: Media, url: URL, bytesWritten: Int64, expectedBytes: Int64? = nil, createdAt: Date, updatedAt: Date, attempts: Int = 0) {
        self.origin = origin
        self.url = url
        self.bytesWritten = bytesWritten
        self.expectedBytes = expectedBytes
        self.attempts = attempts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
