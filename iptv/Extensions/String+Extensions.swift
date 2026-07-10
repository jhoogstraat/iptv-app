//
//  String+Extensions.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 19.03.26.
//

import Foundation

extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Substring {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
