//
//  Source.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 17.03.26.
//

import Foundation
import SwiftData

@Model final class MediaSource: Identifiable {
    var url: URL
    var streamBitrate: Int?
    var audioDescription: String?
    var resolution: String?
    var framerate: Double?
    
    var media: PlayableMedia!

    init(url: URL, streamBitrate: Int? = nil, audioDescription: String? = nil, videoResolution: String? = nil, videoFrameRate: Double? = nil) {
        self.url = url
        self.streamBitrate = streamBitrate
        self.audioDescription = audioDescription
        self.resolution = videoResolution
        self.framerate = videoFrameRate
    }
}
