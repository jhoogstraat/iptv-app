//
//  VLCCompatibility.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import Foundation

#if canImport(MobileVLCKit)
import MobileVLCKit
typealias VLCPlayerReference = VLCMediaPlayer
#else
typealias VLCPlayerReference = NSObject
#endif
