//
//  Model+Extensions.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 21.03.26.
//

import SwiftData

extension PersistentModel {
    static func all(modelContext: ModelContext) throws -> [Self] {
        try modelContext.fetch(FetchDescriptor<Self>())
    }

    static func first(modelContext: ModelContext) throws -> Self? {
        var descriptor = FetchDescriptor<Self>()
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).first
    }

    static func count(modelContext: ModelContext) throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<Self>())
    }

    static func ids(modelContext: ModelContext) throws -> [PersistentIdentifier] {
        try modelContext.fetchIdentifiers(FetchDescriptor<Self>())
    }

    static func id(_ id: PersistentIdentifier, modelContext: ModelContext) -> Self? {
        modelContext.registeredModel(for: id)
    }

    static func delete(_ model: Self, modelContext: ModelContext) {
        modelContext.delete(model)
    }

    static func deleteAll(modelContext: ModelContext) throws {
        try all(modelContext: modelContext).forEach { modelContext.delete($0) }
    }
}
