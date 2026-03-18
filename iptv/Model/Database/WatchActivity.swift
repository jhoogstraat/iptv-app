//
//  WatchActivity.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 16.03.26.
//

import Foundation
import SwiftData

@Model final class WatchActivity {
    
    var media: Media
    
    var timestamp: Double
    
    var progress: Double
    
    var isCompleted: Bool
    
    init(media: Media, timestamp: Double, progress: Double, isCompleted: Bool) {
        self.media = media
        self.timestamp = timestamp
        self.progress = progress
        self.isCompleted = isCompleted
    }
    
}
