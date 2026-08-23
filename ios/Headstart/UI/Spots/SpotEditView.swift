// ios/Headstart/UI/Spots/SpotEditView.swift
import SwiftUI
import MapKit

/// What the editor produces. A named type rather than five positional parameters, because
/// `(String, Double, Double, Int, Double)` is a trap: two of those are coordinates and two are
/// limits, and swapping either pair compiles silently.
///
/// Both numeric fields are clamped to ADDENDUM §K on the way in, so a draft can only ever hold
/// a value the server will accept. `SpotRepository.upsert` clamps again — the clamps are
/// idempotent, and the point is that no layer trusts the one above it.
public struct SpotDraft: Equatable, Sendable {
    public let name: String
    public let lat: Double
    public let lng: Double
    public let leadTimeMin: Int
    public let radiusM: Double

    public init(name: String, lat: Double, lng: Double, leadTimeMin: Int, radiusM: Double) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lat = lat
        self.lng = lng
        self.leadTimeMin = SpotLimits.clampLeadTimeMin(leadTimeMin)
        self.radiusM = SpotLimits.clampRadiusM(radiusM)
    }
}

/// `design/SpotEdit.dc.html`. The camera moves under a fixed centre pin; whatever the pin is
/// over when you tap Save is the spot. The dashed circle is `radiusM`.
///
/// MapKit needs no API key and no billing surface, which is why the place picker is a real map
/// even though the routing story (decision D7) is deliberately on-device too.
public struct SpotEditView: View {

    @State private var name: String
    @State private var leadTimeMin: Double
    @State private var radiusM: Int
    @State private var centre: CLLocationCoordinate2D
    @State private var camera: MapCameraPosition
    @State private var busy = false
    @State private var errorText: String?
    @FocusState private var nameFocused: Bool

    private let isEditing: Bool
    private let onBack: () -> Void
    private let onSave: (SpotDraft) async -> String?
    private let onDelete: (() async -> String?)?

    /// The four radii the artboard offers. All four are inside the contract's 50–500.
    static let radiusChoices = [50, 100, 200, 500]
    /// The slider's range. Narrower than the contract's 1–30 on purpose (`SpotEdit.dc.html`),
    /// so everything it can produce is inside the clamp.
    static let leadTimeSliderRange = 1.0...15.0

    /// - Parameters:
    ///   - existing: nil when adding.
    ///   - startCoordinate: where to open the map when adding — the device's location.
    ///   - onSave: returns an error message to show inline, or nil on success.
    ///   - onDelete: nil when adding; the screen shows no destructive button then.
    public init(
        existing: Spot?,
        startCoordinate: CLLocationCoordinate2D,
        onBack: @escaping () -> Void,
        onSave: @escaping (SpotDraft) async -> String?,
        onDelete: (() async -> String?)? = nil
    ) {
        self.isEditing = existing != nil
        self.onBack = onBack
        self.onSave = onSave
        self.onDelete = onDelete

        let coordinate = existing.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
        } ?? startCoordinate

        _name = State(initialValue: existing?.name ?? "")
        _leadTimeMin = State(
            initialValue: Double(SpotLimits.clampLeadTimeMin(
                existing?.leadTimeMin ?? SpotLimits.defaultLeadTimeMin
            ))
        )
        _radiusM = State(
            initialValue: Int(SpotLimits.clampRadiusM(existing?.radiusM ?? SpotLimits.defaultRadiusM))
        )
        _centre = State(initialValue: coordinate)
        _camera = State(initialValue: .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 700,
            longitudinalMeters: 700
        )))
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var draft: SpotDraft {
        SpotDraft(
            name: trimmedName,
            lat: centre.latitude,
            lng: centre.longitude,
            leadTimeMin: Int(leadTimeMin),
            radiusM: Double(radiusM)
        )
    }

    public var body: some View {
        ZStack {
            HS.base.ignoresSafeArea()

            VStack(spacing: 0) {
                mapPanel
                editorPanel
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
    }

    private var mapPanel: some View {
        ZStack(alignment: .top) {
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                MapCircle(center: centre, radius: CLLocationDistance(radiusM))
                    .foregroundStyle(HS.go.opacity(0.07))
                    .stroke(HS.go.opacity(0.32), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .continuous) { context in
                centre = context.region.center
            }

            // The pin never moves; the map does.
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(HS.go)
                .shadow(radius: 6)
                .frame(maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            HStack {
                HSIconButton(systemImage: "chevron.left", tint: HS.text, corner: 14, action: onBack)
                    .accessibilityLabel("Back")
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 70)

            VStack {
                Spacer()
                LinearGradient(
                    colors: [HS.base.opacity(0), HS.base],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 56)
                .allowsHitTesting(false)
            }
        }
        .frame(height: 264)
        .clipped()
    }

    private var editorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                nameField
                leadTimeCard
                radiusRow

                if let errorText {
                    Text(errorText).font(.hs(14)).foregroundStyle(HS.delayed)
                }

                VStack(spacing: 12) {
                    HSButton("Save spot", enabled: !trimmedName.isEmpty && !busy) {
                        busy = true
                        errorText = nil
                        let value = draft
                        Task {
                            errorText = await onSave(value)
                            busy = false
                        }
                    }
                    if let onDelete {
                        HSButton("Delete this spot", kind: .destructive, enabled: !busy) {
                            busy = true
                            errorText = nil
                            Task {
                                errorText = await onDelete()
                                busy = false
                            }
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 38)
            }
            .padding(.horizontal, HS.screenPadding)
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 9) {
            HSSectionLabel(isEditing ? "Spot name" : "New spot name")
            TextField("Office", text: $name)
                .font(.hs(18, .medium))
                .foregroundStyle(HS.text)
                .autocorrectionDisabled()
                .focused($nameFocused)
                .padding(.horizontal, 18)
                .frame(height: HS.controlHeight)
                .background(HS.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(nameFocused ? HS.go : HS.line, lineWidth: nameFocused ? 1.5 : 1)
                )
                // The server rejects a name over 40 characters with `bad-name`; the field
                // simply cannot hold one.
                .onChange(of: name) { _, value in
                    if value.count > 40 { name = String(value.prefix(40)) }
                }
                .accessibilityLabel("Spot name")
        }
    }

    private var leadTimeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HSSectionLabel("Your headstart")
            Text("How long from your desk to the curb? Only the person waiting here can change this.")
                .font(.hs(16))
                .lineSpacing(3)
                .foregroundStyle(HS.text2)

            HSCard(padding: 20) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(Int(leadTimeMin))")
                            .font(.hsNum(52, .bold))
                            .tracking(-2)
                            .foregroundStyle(HS.headstart)
                        Text(Int(leadTimeMin) == 1 ? "minute" : "minutes")
                            .font(.hs(20, .medium))
                            .foregroundStyle(HS.text2)
                    }
                    Slider(value: $leadTimeMin, in: Self.leadTimeSliderRange, step: 1)
                        .tint(HS.headstart)
                        .accessibilityLabel("Headstart in minutes")
                    HStack {
                        Text("\(Int(Self.leadTimeSliderRange.lowerBound)) min")
                        Spacer()
                        Text("\(Int(Self.leadTimeSliderRange.upperBound)) min")
                    }
                    .font(.hsNum(13, .regular))
                    .foregroundStyle(HS.text3)
                }
            }
        }
    }

    private var radiusRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Arrival radius").font(.hs(16, .semibold)).foregroundStyle(HS.text)
                Text("counts as arrived within").font(.hs(14)).foregroundStyle(HS.text3)
            }
            Spacer()
            Menu {
                ForEach(Self.radiusChoices, id: \.self) { value in
                    Button("\(value) m") { radiusM = value }
                }
            } label: {
                Text("\(radiusM) m")
                    .font(.hsNum(16, .semibold))
                    .foregroundStyle(HS.text)
                    .padding(.horizontal, 16)
                    .frame(height: HS.minTouchTarget)
                    .background(HS.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(HS.line, lineWidth: 1)
                    )
            }
            .accessibilityLabel("Arrival radius in metres")
        }
    }
}

/// Dhaka — the same city the drive-replay waypoints use.
private let previewStart = CLLocationCoordinate2D(latitude: 23.7806, longitude: 90.4193)

#Preview("Spot edit — new") {
    SpotEditView(
        existing: nil,
        startCoordinate: previewStart,
        onBack: {},
        onSave: { _ in nil }
    )
}

#Preview("Spot edit — existing") {
    SpotEditView(
        existing: SpotPreviewData.spot(id: "s3", name: "Airport", leadTimeMin: 12, radiusM: 500),
        startCoordinate: previewStart,
        onBack: {},
        onSave: { _ in nil },
        onDelete: { nil }
    )
}

#Preview("Spot edit — save failed") {
    SpotEditView(
        existing: SpotPreviewData.spot(id: "s1", name: "Office", leadTimeMin: 3),
        startCoordinate: previewStart,
        onBack: {},
        onSave: { _ in HeadstartError.badName.userMessage },
        onDelete: { HeadstartError.offline.userMessage }
    )
}
