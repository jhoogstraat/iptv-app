import Foundation
import SwiftUI

enum TrailerURLResolver {
    static func url(from rawValue: String?) -> URL? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        if let url = URL(string: value), url.scheme == "https" || url.scheme == "http" {
            return url
        }
        var components = URLComponents(string: "https://www.youtube.com/watch")
        components?.queryItems = [URLQueryItem(name: "v", value: value)]
        return components?.url
    }
}

struct DetailMetadataRow: Identifiable {
    let label: String
    let value: String?

    var id: String { label }

    var displayValue: String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "Not available"
        }
        return value
    }
}

struct DetailMetadataGrid: View {
    let rows: [DetailMetadataRow]
    let isLoading: Bool

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading details…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
                    .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: DetailSpacing.sm) {
                    ForEach(rows) { row in
                        LabeledContent(row.label, value: row.displayValue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(DetailSpacing.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .animation(.smooth(duration: 0.35), value: isLoading)
    }
}

extension View {
    @ViewBuilder
    func detailNavigationChrome(title: String, artworkURL: URL?, progress: CGFloat) -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    DetailCollapsedHeaderBar(
                        title: title,
                        artworkURL: artworkURL,
                        titleArtworkURL: nil,
                        progress: progress
                    )
                }
            }
        #elseif os(visionOS)
        toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    DetailCollapsedHeaderBar(
                        title: title,
                        artworkURL: artworkURL,
                        titleArtworkURL: nil,
                        progress: progress
                    )
                }
            }
        #else
        self
        #endif
    }
}
