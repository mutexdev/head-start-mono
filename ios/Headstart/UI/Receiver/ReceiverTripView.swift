// ios/Headstart/UI/Receiver/ReceiverTripView.swift
import SwiftUI
import MapKit

/// `design/ReceiverTrip.dc.html`.
///
/// ─────────────────────────────────────────────────────────────────────────────────────────
/// THIS SCREEN READS `trip.receiverView` AND NOTHING ELSE FOR POSITION AND ETA.
///
/// CLIENT_CONTRACT.md line 39 and CLIENT_CONTRACT_ADDENDUM.md §H forbid a receiver surface from
/// rendering the driver's raw position field, so that fuzzy mode stays a server-side guarantee
/// rather than a client-side promise. §H makes it structural: the forbidden field's name must
/// not appear anywhere under `ios/Headstart/UI/Receiver/`, and a grep for it is a done-criterion
/// on both platforms — which is why this comment describes the rule without spelling the token,
/// and why even the preview fixtures live in `UI/Driver/TripPreviewData`.
///
/// It is enforced three deep, so no single slip can undo it:
///   1. the `Trip` model has no top-level property for that field at all — it is present in
///      every snapshot this screen's listener receives, and is simply unreachable from Swift;
///   2. the fuzzed projection the server DOES publish is `ReceiverView.point`, named after what
///      it is rather than after the server key it was read from, so drawing the dot cannot
///      reintroduce the token;
///   3. nothing in this file, comments included, names it.
///
/// In fuzzy mode the server omits the point from the projection, so `point` is nil, the map
/// draws no driver dot and the subtitle drops the distance. There is no client-side "should I
/// hide this?" branch, because there is nothing for the client to decide.
/// ─────────────────────────────────────────────────────────────────────────────────────────
///
/// `onReply` takes the closed `ReplyKind` (ADDENDUM §B — exactly four kinds; being late is the
/// driver's `setRunningLate` callable and arrives as a push, never as a reply). It returns an
/// error message to render inline, or nil on success; empty custom text comes back as
/// `bad-reply` (ADDENDUM §O) and `TripRepository.sendReply` rejects it without a round trip.
public struct ReceiverTripView: View {

    @State private var busy = false
    @State private var errorText: String?
    @State private var customText = ""
    @State private var showingCustom = false
    @FocusState private var customFocused: Bool

    private let trip: Trip
    private let partnerName: String
    private let onReply: (ReplyKind, String?) async -> String?

    public init(
        trip: Trip,
        partnerName: String = PartnerName.fallback,
        onReply: @escaping (ReplyKind, String?) async -> String?
    ) {
        self.trip = trip
        self.partnerName = partnerName
        self.onReply = onReply
    }

    /// The ONLY position/ETA source this screen may read.
    private var projection: ReceiverView? { trip.receiverView }

    /// `trip.eta` is the driver-facing number and is only the fallback for the header when the
    /// server has not written the projection yet (the first seconds of a trip).
    private var etaSec: Int { projection?.etaSeconds ?? trip.eta?.seconds ?? 0 }

    /// Anchored to when the server last updated the ETA, so the countdown stays honest between
    /// pushes instead of drifting by however long the document took to arrive.
    private var walkOutAt: Date {
        let anchorMs = trip.eta?.updatedAt ?? nowMs()
        let secondsFromAnchor = max(0, etaSec - trip.leadTimeMin * 60)
        return Date(timeIntervalSince1970: Double(anchorMs) / 1000 + Double(secondsFromAnchor))
    }

    private var remainingMetres: Double? {
        guard let point = projection?.point else { return nil }
        return haversineMeters(point.lat, point.lng, trip.spot.lat, trip.spot.lng)
    }

    public var body: some View {
        ZStack {
            HS.base.ignoresSafeArea()
            VStack(spacing: 0) {
                mapPanel
                detailPanel
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Map

    private var mapPanel: some View {
        ZStack(alignment: .topLeading) {
            Map(
                initialPosition: .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: trip.spot.lat, longitude: trip.spot.lng),
                    latitudinalMeters: 4_000,
                    longitudinalMeters: 4_000
                )),
                interactionModes: []
            ) {
                if let polyline = trip.routePolyline {
                    // `decodePolyline` is CoreLocation-free by design (it has to unit-test with
                    // no simulator services), so it hands back `HSCoordinate`. Same member
                    // names, one map to cross the boundary.
                    let coordinates = decodePolyline(polyline).map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    }
                    if coordinates.count > 1 {
                        MapPolyline(coordinates: coordinates)
                            .stroke(
                                HS.go.opacity(0.85),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                            )
                    }
                }
                Marker(
                    trip.spot.name,
                    systemImage: "mappin",
                    coordinate: CLLocationCoordinate2D(latitude: trip.spot.lat, longitude: trip.spot.lng)
                )
                .tint(HS.go)
                // Nil in fuzzy mode — the server decided, not this screen.
                if let point = projection?.point {
                    Annotation(
                        "",
                        coordinate: CLLocationCoordinate2D(latitude: point.lat, longitude: point.lng)
                    ) {
                        ZStack {
                            Circle().fill(HS.text.opacity(0.09)).frame(width: 38, height: 38)
                            Circle().fill(HS.text).frame(width: 22, height: 22)
                            Circle().fill(HS.base).frame(width: 9, height: 9)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))

            HStack(spacing: 9) {
                Circle().fill(HS.go).frame(width: 7, height: 7)
                Text("\(partnerName) is driving")
                    .font(.hs(13, .semibold))
                    .foregroundStyle(HS.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(HS.base.opacity(0.86))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(HS.line, lineWidth: 1))
            .padding(.leading, HS.screenPadding)
            .padding(.top, 70)

            VStack {
                Spacer()
                LinearGradient(
                    colors: [HS.base.opacity(0), HS.base],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 70)
                .allowsHitTesting(false)
            }
        }
        .frame(height: 330)
        .clipped()
    }

    // MARK: - Detail

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HSSectionLabel("Your headstart", color: HS.headstart)
            Spacer().frame(height: 8)

            // Ticks locally once a second — no push is needed to move the number.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = Int(walkOutAt.timeIntervalSince(context.date).rounded())
                HSBigNumber(
                    value: formatCountdown(remaining),
                    unit: remaining > 0 ? "until you walk out" : "walk out now",
                    size: 56,
                    tracking: -2.4,
                    color: remaining > 0 ? HS.text : HS.headstart
                )
            }

            Spacer().frame(height: 18)
            HSProgressBar(fraction: progressFraction(projection?.progressPct ?? 0))
            Spacer().frame(height: 10)

            HStack(spacing: 0) {
                Text(trip.startedAt.map { "Started \(clockAt($0))" } ?? "Started")
                    .font(.hs(13))
                    .foregroundStyle(HS.text3)
                Spacer(minLength: 8)
                Text("Arrives ").font(.hs(13)).foregroundStyle(HS.text3)
                Text(arrivalClock(nowMs: nowMs(), etaSec: etaSec))
                    .font(.hsNum(13, .semibold))
                    .foregroundStyle(HS.text2)
            }

            Spacer().frame(height: 22)

            HSCard(padding: 18) {
                HStack(spacing: 15) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(HS.text2)
                        .frame(width: 42, height: 42)
                        .background(HS.raised)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(minutesAway(etaSec)) min away")
                            .font(.hs(16, .semibold))
                            .foregroundStyle(HS.text)
                        Text(subtitle)
                            .font(.hs(14))
                            .foregroundStyle(HS.text3)
                    }
                    Spacer(minLength: 0)
                }
            }

            if let errorText {
                Spacer().frame(height: 14)
                Text(errorText).font(.hs(14)).foregroundStyle(HS.delayed)
            }

            Spacer()

            replyBar
        }
        .padding(.horizontal, HS.screenPadding)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let metres = remainingMetres { parts.append(formatDistance(metres)) }
        if trip.eta?.approximate == true {
            parts.append("ETA is approximate")
        } else if trip.alerts.slipCount > 0 {
            parts.append("traffic pushed this back")
        } else {
            parts.append("traffic is normal")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Quick replies

    private var replyBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HSSectionLabel("Quick reply")
                .padding(.bottom, 3)

            HStack(spacing: 9) {
                HSChip("5 more min") { send(.fiveMore) }
                HSChip("Take your time") { send(.takeYourTime) }
                Spacer(minLength: 0)
            }

            HStack(spacing: 9) {
                HSChip("I'm at \(trip.spot.name)") { send(.atSpot) }
                HSChip(showingCustom ? "Never mind" : "Something else") {
                    showingCustom.toggle()
                    customFocused = showingCustom
                    if !showingCustom { customText = "" }
                }
                Spacer(minLength: 0)
            }

            if showingCustom {
                HStack(spacing: 10) {
                    TextField("", text: $customText, prompt: Text("Type a message").foregroundStyle(HS.text3))
                        .font(.hs(15))
                        .foregroundStyle(HS.text)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.send)
                        .focused($customFocused)
                        .onSubmit { sendCustom() }
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .background(HS.card)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(HS.line, lineWidth: 1))

                    Button(action: sendCustom) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(canSendCustom ? HS.goInk : HS.text3)
                            .frame(width: HS.minTouchTarget, height: HS.minTouchTarget)
                            .background(canSendCustom ? HS.go : HS.raised)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSendCustom)
                    .accessibilityLabel("Send message")
                }
            }
        }
        .disabled(busy)
        .opacity(busy ? 0.6 : 1)
        .padding(.bottom, 38)
    }

    private var canSendCustom: Bool {
        !busy && !customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendCustom() {
        guard canSendCustom else { return }
        let text = customText
        send(.custom, text: text)
        customText = ""
        showingCustom = false
        customFocused = false
    }

    private func send(_ kind: ReplyKind, text: String? = nil) {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task {
            errorText = await onReply(kind, text)
            busy = false
        }
    }
}

// MARK: - Previews

#Preview("Receiver trip") {
    ReceiverTripView(
        trip: TripPreviewData.trip(
            receiverView: TripPreviewData.receiverView(
                etaSeconds: 1_080, progressPct: 47, point: (lat: 23.8100, lng: 90.4500)
            )
        ),
        partnerName: "Mostafi",
        onReply: { _, _ in nil }
    )
}

#Preview("Receiver trip — fuzzy, no dot, no distance") {
    ReceiverTripView(
        trip: TripPreviewData.trip(
            receiverView: TripPreviewData.receiverView(etaSeconds: 420, progressPct: 78),
            routePolyline: nil
        ),
        partnerName: "Mostafi",
        onReply: { _, _ in nil }
    )
}

#Preview("Receiver trip — walk out now, traffic slipped") {
    ReceiverTripView(
        trip: TripPreviewData.trip(
            etaSeconds: 90,
            alerts: ["started": true, "tenMin": true, "leadTime": true, "slipCount": 3],
            receiverView: TripPreviewData.receiverView(etaSeconds: 90, progressPct: 96)
        ),
        partnerName: "Mostafi",
        onReply: { _, _ in nil }
    )
}

#Preview("Receiver trip — reply rejected, unnamed partner") {
    ReceiverTripView(
        trip: TripPreviewData.trip(),
        onReply: { _, _ in HeadstartError.badReply.userMessage }
    )
}
