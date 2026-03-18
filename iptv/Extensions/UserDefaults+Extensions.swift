//
//  UserDefaults+Extensions.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 18.03.26.
//

import Foundation

enum UserDefaultKey: String {
    case activeSession = "active_session"
}

extension UserDefaults {
    
    func set(_ value: Any?, for key: UserDefaultKey) {
        self.set(value, forKey: key.rawValue)
    }
    
    func object(for key: UserDefaultKey) -> Any? {
        return self.object(forKey: key.rawValue)
    }
    
    func string(for key: UserDefaultKey) -> String? {
        return self.string(forKey: key.rawValue)
    }
    
    func removeObject(for key: UserDefaultKey) {
        self.removeObject(forKey: key.rawValue)
    }
}
