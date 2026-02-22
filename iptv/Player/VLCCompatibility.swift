//
//  VLCCompatibility.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import Foundation

#if canImport(VLCKit)
import VLCKit
typealias VLCPlayerReference = VLCMediaPlayer
#else
typealias VLCPlayerReference = NSObject
#endif
