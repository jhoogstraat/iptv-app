import SQLiteData
import SwiftUI

struct LibraryCategoryList<Destination: View>: View {
    let categories: [Category]
    let hydrationSnapshot: LibraryHydrationSnapshot
    let contentName: String
    @ViewBuilder let destination: (Category) -> Destination

    private var sections: [(key: String, categories: [Category])] {
        Dictionary(grouping: categories) { category in
            category.groupKey
        }
        .map { key, categories in
            (
                key,
                categories.sorted { lhs, rhs in
                    let comparison = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
                    return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
                }
            )
        }
        .sorted { lhs, rhs in
            CategoryGrouping.title(for: lhs.key)
                .localizedStandardCompare(CategoryGrouping.title(for: rhs.key)) == .orderedAscending
        }
    }

    var body: some View {
        List {
            ForEach(sections, id: \.key) { section in
                Section(CategoryGrouping.title(for: section.key)) {
                    ForEach(section.categories) { category in
                        NavigationLink {
                            destination(category)
                        } label: {
                            LibraryCategoryRow(
                                category: category,
                                contentName: contentName,
                                hydrationState: hydrationSnapshot.state(for: category)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens this category")
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #endif
    }
}

private struct LibraryCategoryRow: View {
    let category: Category
    let contentName: String
    let hydrationState: SyncManager.CategoryHydrationState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.3.group.bubble")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(.rect(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(category.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var statusText: String {
        switch hydrationState {
        case .unhydrated:
            "Not loaded yet"
        case .loading:
            "Loading \(pluralContentName)"
        case .empty:
            "Loaded, no \(pluralContentName)"
        case let .populated(count):
            "\(count) local \(count == 1 ? contentName : pluralContentName)"
        case .failed:
            "Failed to load"
        }
    }

    private var pluralContentName: String {
        contentName == "series" ? contentName : "\(contentName)s"
    }
}

struct LibraryShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.20), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: max(proxy.size.width * 0.45, 1))
                        .rotationEffect(.degrees(18))
                        .offset(x: phase * proxy.size.width * 1.6)
                    }
                    .allowsHitTesting(false)
                    .clipped()
                }
            }
            .onAppear {
                guard !reduceMotion, phase < 0 else { return }
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    phase = 1.1
                }
            }
    }
}

extension View {
    func libraryShimmer() -> some View {
        modifier(LibraryShimmerModifier())
    }
}
