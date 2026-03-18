//
//  SessionManager.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 17.03.26.
//

import SwiftUI
import SwiftData

@Observable
class SessionManager {
    // Deps
    private let userDefaults: UserDefaults
    private let modelContainer: ModelContainer
    
    // Constants
    private let activeProviderKey = "active_provider_id"
    
    // State
    var session: ActiveSession?

    // Dependent state
    var hasActiveSession: Bool { session != nil }
    
    init(userDefaults: UserDefaults, modelContainer: ModelContainer) {
        self.userDefaults = userDefaults
        self.modelContainer = modelContainer
    }
    
    func load(key: UserDefaultKey) {
        guard let id = userDefaults.string(for: key), let uuid = UUID(uuidString: id), let provider = Provider.with(id: uuid, in: modelContainer.mainContext) else { return }
        
        self.session = self.build(for: provider)
    }
    
    func initialize(provider: Provider) {
        self.modelContainer.mainContext.insert(provider)
        userDefaults.set(provider.id.uuidString, for: .activeSession)
        self.session = self.build(for: provider)
    }
    
    func change(to id: Provider.ID) {
        guard let provider = Provider.with(id: id, in: modelContainer.mainContext) else { return }
        
        userDefaults.set(provider, forKey: activeProviderKey)
        self.session = self.build(for: provider)
    }
    
    func clear() {
        guard let session else { return }
        
        modelContainer.mainContext.delete(session.provider)
        userDefaults.removeObject(for: .activeSession)
        self.session = nil
    }
    
    private func build(for provider: Provider) -> ActiveSession? {
        if let provider = provider as? XtreamProvider {
            let service = XtreamService(.shared, baseURL: provider.endpoint, username: provider.username, password: provider.password)
            return ActiveSession(provider: provider, service: service)
        }
        
        fatalError("Unknown provider type encountered. Fix before release.")
    }
    
}

@Observable
class ActiveSession {
    let provider: Provider
    let service: XtreamService
    
    init(provider: Provider, service: XtreamService) {
        self.provider = provider
        self.service = service
    }
}
