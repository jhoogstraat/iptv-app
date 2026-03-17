//
//  WatchActivity.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 16.03.26.
//

import Foundation
import SwiftData

@Model final class WatchActivity {
    
    @Relationship
    var media: Media
    
    var progress: Double
    
    var isCompleted: Bool
    
    init(media: Media, progress: Double, isCompleted: Bool) {
        self.media = media
        self.progress = progress
        self.isCompleted = isCompleted
    }
    
}
