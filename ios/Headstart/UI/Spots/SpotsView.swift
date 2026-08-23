// ios/Headstart/UI/Spots/SpotsView.swift
import SwiftUI

/// `design/Spots.dc.html`.
///
/// `partnerName` is already resolved by the caller through `PartnerName.resolve(pair:selfUid:)`,
/// which never returns nil — an unnamed or still-pending partner is the string "Your partner".
/// Resolving it here would mean handing a view a `Pair`, and these screens deliberately take
/// data and closures only.
public struct SpotsView: View {

    private let spots: [Spot]
    private let partnerName: String
    private let onBack: () -> Void
    private let onAdd: () -> Void
    private let onEdit: (Spot) -> Void

    public init(
        spots: [Spot],
        partnerName: String = PartnerName.fallback,
        onBack: @escaping () -> Void,
        onAdd: @escaping () -> Void,
        onEdit: @escaping (Spot) -> Void
    ) {
        self.spots = spots
        self.partnerName = partnerName
        self.onBack = onBack
        self.onAdd = onAdd
        self.onEdit = onEdit
    }

    public var body: some View {
        HSScreen {
            Spacer().frame(height: 26)
            HSBackBar(action: onBack)
            Spacer().frame(height: 8)

            HStack {
                Text("Pickup spots")
                    .font(.hs(30, .bold))
                    .tracking(-1)
                    .foregroundStyle(HS.text)
                Spacer()
                HSIconButton(systemImage: "plus", tint: HS.go, corner: 14, action: onAdd)
                    .accessibilityLabel("Add a spot")
            }

            Spacer().frame(height: 10)
            Text("Each spot remembers how much headstart the person waiting there needs.")
                .font(.hs(15))
                .lineSpacing(3)
                .foregroundStyle(HS.text2)

            Spacer().frame(height: 26)

            if spots.isEmpty {
                HSCard(padding: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No spots yet").font(.hs(17, .semibold)).foregroundStyle(HS.text)
                        Text("Add the place you get picked up from — the office door, the gym, the airport.")
                            .font(.hs(14))
                            .lineSpacing(3)
                            .foregroundStyle(HS.text2)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(spots) { spot in
                            HSListRow(
                                systemImage: Self.icon(for: spot.name),
                                title: spot.name,
                                subtitle: "\(partnerName) walks out \(spot.leadTimeMin) min early"
                            ) { onEdit(spot) }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Spacer()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(HS.text3)
                Text("Whoever waits at a spot sets its headstart — you can't set it for them.")
                    .font(.hs(14))
                    .lineSpacing(3)
                    .foregroundStyle(HS.text3)
            }
            .padding(.bottom, 44)
        }
    }

    /// Cosmetic only — the artboards use a house, a dumbbell and a plane.
    static func icon(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("gym") { return "dumbbell" }
        if lower.contains("airport") { return "airplane" }
        if lower.contains("home") { return "house" }
        return "building.2"
    }
}

// MARK: - Preview data
//
// `Spot` has only a Firestore mapper (`init?(id:data:)`) on purpose — no second, divergent
// initialiser gets added just to make previews convenient. Sample data therefore goes in
// through the same dictionary the server would send, which also keeps the mapper honest.
// Not DEBUG-gated: `#Preview` bodies compile in every configuration, so gating the data they
// reference would break the Release build.

enum SpotPreviewData {
    static func spot(
        id: String,
        name: String,
        leadTimeMin: Int,
        radiusM: Double = 100,
        createdAt: Int64 = 0
    ) -> Spot {
        Spot(id: id, data: [
            "pairId": "pair1",
            "name": name,
            "lat": 23.7806,
            "lng": 90.4193,
            "radiusM": radiusM,
            "leadTimeMin": leadTimeMin,
            "createdBy": "uidA",
            "createdAt": createdAt,
        ])!
    }

    static let all: [Spot] = [
        spot(id: "s1", name: "Office", leadTimeMin: 3, createdAt: 1),
        spot(id: "s2", name: "Gym", leadTimeMin: 5, radiusM: 50, createdAt: 2),
        spot(id: "s3", name: "Airport", leadTimeMin: 12, radiusM: 500, createdAt: 3),
    ]
}

#Preview("Spots") {
    SpotsView(
        spots: SpotPreviewData.all,
        partnerName: "Sara",
        onBack: {},
        onAdd: {},
        onEdit: { _ in }
    )
}

#Preview("Spots — empty, unnamed partner") {
    SpotsView(spots: [], onBack: {}, onAdd: {}, onEdit: { _ in })
}
