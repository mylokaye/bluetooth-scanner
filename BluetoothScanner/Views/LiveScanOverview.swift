import SwiftUI

struct CategoryOverviewGrid: View {
    let summaries: [KnownDeviceCategorySummary]
    @Binding var selectedCategory: KnownDeviceCategorySummary?

    var body: some View {
        if summaries.isEmpty {
            ContentUnavailableView(
                "No devices yet",
                systemImage: "antenna.radiowaves.left.and.right",
                description: Text("Start scanning to populate categories.")
            )
        } else {
            SummaryGrid {
                ForEach(summaries) { summary in
                    Button {
                        selectedCategory = summary
                    } label: {
                        CategorySummaryTile(summary: summary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct ManufacturerOverviewGrid: View {
    let summaries: [KnownDeviceManufacturerSummary]
    @Binding var selectedManufacturer: KnownDeviceManufacturerSummary?

    var body: some View {
        if summaries.isEmpty {
            ContentUnavailableView(
                "No manufacturers yet",
                systemImage: "building.2",
                description: Text("Start scanning to populate manufacturers.")
            )
        } else {
            SummaryGrid {
                ForEach(summaries) { summary in
                    Button {
                        selectedManufacturer = summary
                    } label: {
                        ManufacturerSummaryTile(summary: summary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct SummaryGrid<Content: View>: View {
    private static var cardSpacing: CGFloat { 10 }

    private let content: Content
    private let horizontalOutset: CGFloat

    init(horizontalOutset: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.horizontalOutset = horizontalOutset
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 0), spacing: Self.cardSpacing),
                GridItem(.flexible(minimum: 0), spacing: Self.cardSpacing)
            ],
            spacing: Self.cardSpacing
        ) {
            content
        }
        .padding(.horizontal, -horizontalOutset)
        .padding(.top, -2)
        .padding(.bottom, 4)
    }
}

private struct OverviewSummaryTile<Mark: View>: View {
    let count: Int
    let accessibilityLabel: String
    private let mark: Mark

    init(
        count: Int,
        accessibilityLabel: String,
        @ViewBuilder mark: () -> Mark
    ) {
        self.count = count
        self.accessibilityLabel = accessibilityLabel
        self.mark = mark()
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                VStack(spacing: 14) {
                    Text(count, format: .number)
                        .font(.largeTitle.monospacedDigit())
                        .foregroundStyle(.primary.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    mark
                        .frame(height: 36)
                        .frame(maxWidth: .infinity)
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct CategorySummaryTile: View {
    let summary: KnownDeviceCategorySummary

    var body: some View {
        OverviewSummaryTile(
            count: summary.count,
            accessibilityLabel: "\(summary.categoryName), \(summary.count) devices"
        ) {
            Image(systemName: summary.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(height: 18)
        }
    }
}

private struct ManufacturerSummaryTile: View {
    let summary: KnownDeviceManufacturerSummary

    private var logoAsset: ManufacturerLogoAsset? {
        ManufacturerLogoAsset(manufacturerName: summary.manufacturerName)
    }

    var body: some View {
        OverviewSummaryTile(
            count: summary.count,
            accessibilityLabel: "\(summary.manufacturerName), \(summary.count) devices"
        ) {
            manufacturerMark
        }
    }

    @ViewBuilder
    private var manufacturerMark: some View {
        if let logoAsset {
            Image(logoAsset.imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 135, maxHeight: 36)
                .accessibilityHidden(true)
        } else {
            Text(summary.manufacturerName.uppercased())
                .font(.subheadline.weight(.semibold).italic())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .multilineTextAlignment(.center)
        }
    }
}

private struct ManufacturerLogoAsset {
    let imageName: String

    init?(manufacturerName: String, bundle: Bundle = .main) {
        guard let imageName = Self.candidateNames(for: manufacturerName).first(where: { candidate in
            UIImage(named: candidate, in: bundle, compatibleWith: nil) != nil
        }) else {
            return nil
        }

        self.imageName = imageName
    }

    private static func candidateNames(for manufacturerName: String) -> [String] {
        let cleanedName = manufacturerName
            .replacingOccurrences(
                of: #"\b(inc|incorporated|llc|ltd|limited|corp|corporation|company|co|electronics|group)\b\.?"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let words = cleanedName
            .split(separator: " ")
            .map(String.init)

        let fullName = words.joined(separator: " ").localizedCapitalized
        let firstWord = words.first?.localizedCapitalized

        return [fullName, firstWord]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .uniqued()
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
