/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A modifier that creates the a model container for the preview data.
*/

import Foundation
import SwiftData
import SwiftUI


/// A modifier that creates the a model container for the preview data.
struct PreviewData: PreviewModifier {
    static func makeSharedContext() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Video.self, Category.self,
            configurations: config
        )
//        try Importer.importVideoMetadata(into: container.mainContext, isPreview: true)
        return container
    }
    
    func body(content: Content, context: ModelContainer) -> some View {
        let appContainer = try! AppContainer(modelContainer: context)
        content.modelContainer(context)
            .environment(appContainer)
            .environment(appContainer.providerStore)
            .environment(appContainer.catalog)
            .environment(appContainer.player)
            .environment(appContainer.favoritesStore)
            .environment(appContainer.backgroundActivityCenter)
            .environment(appContainer.downloadCenter)
            #if os(visionOS)
            .environment(ImmersiveEnvironment())
            #endif
            #if os(iOS) || os(macOS)
            .preferredColorScheme(.dark)
            #endif
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    @MainActor static var previewData: Self = .modifier(PreviewData())
}

/// The app's sample data.
struct SampleData { }
