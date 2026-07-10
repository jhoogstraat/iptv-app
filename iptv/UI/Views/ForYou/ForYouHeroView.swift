//
//  ForYouHeroView.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import SwiftUI

struct ForYouHeroView: View {
    let hero: ForYouSnapshot.Hero
    let onAction: (ForYouSnapshot.HeroAction) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            heroArtwork
                .accessibilityHidden(true)

            LinearGradient(
                colors: [.clear, .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 14 : 10) {
                Text(hero.reason.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))

                Text(hero.media.title)
                    .font(.title.weight(.bold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if let activity = hero.activity {
                    Text(ForYouWatchProgress.description(for: activity))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                }

                actionLayout
                    .padding(.top, 4)
            }
            .foregroundStyle(.white)
            .padding(heroPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight)
        .background(Color.secondary.opacity(0.2))
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityIdentifier("forYou.hero.\(hero.media.type.rawValue).\(hero.media.sourceID)")
    }

    @ViewBuilder
    private var heroArtwork: some View {
        AsyncImage(url: hero.media.backdropURL ?? hero.media.coverURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .boundedFillArtwork()
            case .empty:
                Rectangle()
                    .fill(.gray.opacity(0.35))
                    .overlay { ProgressView().tint(.white) }
            case .failure:
                artworkFallback
            @unknown default:
                artworkFallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var artworkFallback: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.gray.opacity(0.5), .black.opacity(0.65)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    @ViewBuilder
    private var actionLayout: some View {
        if usesVerticalActions {
            VStack(spacing: 12) {
                actionButton(hero.primaryAction, isPrimary: true)
                if let secondaryAction = hero.secondaryAction {
                    actionButton(secondaryAction, isPrimary: false)
                }
            }
        } else {
            HStack(spacing: 12) {
                actionButton(hero.primaryAction, isPrimary: true)
                if let secondaryAction = hero.secondaryAction {
                    actionButton(secondaryAction, isPrimary: false)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(
        _ action: ForYouSnapshot.HeroAction,
        isPrimary: Bool
    ) -> some View {
        if isPrimary {
            actionButtonLabel(action)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("forYou.hero.action.\(accessibilityActionName(action))")
        } else {
            actionButtonLabel(action)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("forYou.hero.action.\(accessibilityActionName(action))")
        }
    }

    private func actionButtonLabel(_ action: ForYouSnapshot.HeroAction) -> some View {
        Button {
            onAction(action)
        } label: {
            Label(action.title, systemImage: action.systemImage)
                .frame(maxWidth: .infinity, minHeight: minimumButtonHeight)
        }
    }

    private func accessibilityActionName(_ action: ForYouSnapshot.HeroAction) -> String {
        switch action {
        case .resume: "resume"
        case .play: "play"
        case .browseEpisodes: "browseEpisodes"
        case .details: "details"
        }
    }

    private var usesVerticalActions: Bool {
        #if os(tvOS) || os(macOS)
        dynamicTypeSize.isAccessibilitySize
        #else
        horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
        #endif
    }

    private var heroPadding: CGFloat {
        #if os(tvOS)
        32
        #else
        dynamicTypeSize.isAccessibilitySize ? 22 : 18
        #endif
    }

    private var minimumButtonHeight: CGFloat {
        #if os(tvOS)
        64
        #else
        dynamicTypeSize.isAccessibilitySize ? 56 : 44
        #endif
    }

    private var minimumHeight: CGFloat {
        #if os(tvOS)
        520
        #elseif os(macOS)
        dynamicTypeSize.isAccessibilitySize ? 480 : 360
        #else
        if dynamicTypeSize.isAccessibilitySize { return 520 }
        return horizontalSizeClass == .compact ? 420 : 360
        #endif
    }
}
