//
//  ProviderConfigurationProviding.swift
//  iptv
//
//  Created by Codex on 13.03.26.
//

import Foundation

@MainActor
protocol ProviderConfigurationProviding: AnyObject {
    var hasProviderConfiguration: Bool { get }
    var revision: Int { get }

    func requiredConfiguration() throws -> ProviderConfig
}

extension ProviderStore: ProviderConfigurationProviding {
    var hasProviderConfiguration: Bool {
        hasConfiguration
    }
}
