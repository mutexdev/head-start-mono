// ios/Headstart/UI/Driver/DriverTripView.swift
import SwiftUI

/// `design/DriverTrip.dc.html`. Shows the driver exactly what the other person has been told —
/// the whole trust argument of the product is on this screen, which is why the "has been told"
/// timeline renders `trip.alerts` (the SERVER's record of what it sent) rather than anything
/// the client guessed.
///
/// Every number comes from `Format.swift` or the `Trip` model, both already unit-tested. The
/// three closures return an error message to render inline, or nil on success.
///
/// Running late is `setRunningLate(tripId, extraMin)` — a callable, NOT a reply document
/// (CLIENT_CONTRACT_ADDENDUM.md §B). The receiver learns of it through the server's
/// `runningLate` push, so nothing on this screen writes to `replies`.
public struct DriverTripView: View {

    @State private var busy = false
    @State private var errorText: String?

    private let trip: Trip
    private let partnerName: String
    private let latestReply: Reply?
    private let onRunningLate: (Int) async -> String?
    private let onCancel: () async -> String?
    private let onArrived: () async -> String?

    public init(
        trip: Trip,
        partnerName: String = PartnerName.fallback,
        latestReply: Reply? = nil,
        onRunningLate: @escaping (Int) async -> String?,
        onCancel: @escaping () async -> String?,
        onArrived: @escaping () async -> String?
    ) {
        self.trip = trip
        self.partnerName = partnerName
        self.latestReply = latestReply
        self.onRunningLate = onRunningLate
        self.onCancel = onCancel
        self.onArrived = onArrived
    }

    private var etaSec: Int { trip.eta?.seconds ?? 0 }

    public var body: some View {
        HSScreen {
            Spacer().frame(height: 34)

            HStack(spacing: 10) {
                Circle().fill(HS.go).frame(width: 9, height: 9)
                Text("Sharing with \(partnerName)")
                    .font(.hs(14, .semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(HS.go)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("ends on arrival").font(.hs(14)).foregroundStyle(HS.text3)
            }

            Spacer().frame(height: 30)

            HSBigNumber(value: "\(minutesAway(etaSec))", unit: "min away")

            Spacer().frame(height: 10)

            arrivalLine

            Spacer().frame(height: 30)
            Rectangle().fill(HS.line).frame(height: 1)
            Spacer().frame(height: 24)

            HSSectionLabel("What \(partnerName) has been told")
            Spacer().frame(height: 16)

            VStack(alignment: .leading, spacing: 14) {
                toldRow(
                    done: trip.alerts.started,
                    title: "You started driving",
                    trailing: trip.startedAt.map { clockAt($0) } ?? "now",
                    accent: HS.go
                )
                toldRow(
                    done: trip.alerts.tenMin,
                    title: "10 minutes away",
                    trailing: trip.alerts.tenMin ? "sent" : "in \(minutesAway(max(0, etaSec - 600))) min",
                    accent: HS.go
                )
                toldRow(
                    done: trip.alerts.leadTime,
                    title: "Start walking now",
                    accentSuffix: " · \(trip.leadTimeMin) min",
                    trailing: trip.alerts.leadTime ? "sent" : "in \(minutesAway(trip.walkOutSeconds)) min",
                    accent: HS.headstart
                )
            }

            if let latestReply {
                Spacer().frame(height: 26)
                replyCard(latestReply)
            }

            if let errorText {
                Spacer().frame(height: 14)
                Text(errorText).font(.hs(14)).foregroundStyle(HS.delayed)
            }

            Spacer()

            VStack(spacing: 12) {
                HStack(spacing: 9) {
                    lateButton(label: "Late +5", minutes: 5)
                    lateButton(label: "+10", minutes: 10)
                    lateButton(label: "+15", minutes: 15)
                    smallButton(label: "Cancel", tint: HS.delayed) { await onCancel() }
                }

                Button { run { await onArrived() } } label: {
                    Text("I'm here")
                        .font(.hs(18, .bold))
                        .foregroundStyle(HS.goInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(HS.go)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .opacity(busy ? 0.6 : 1)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
            .padding(.bottom, 38)
        }
    }

    // MARK: -

    private var arrivalLine: some View {
        HStack(spacing: 0) {
            Text("Arriving at \(trip.spot.name) around ")
                .font(.hs(17))
                .foregroundStyle(HS.text2)
            Text(arrivalClock(nowMs: nowMs(), etaSec: etaSec))
                .font(.hsNum(17, .semibold))
                .foregroundStyle(HS.text)
            if trip.eta?.approximate == true {
                Text(" (approx.)").font(.hs(17)).foregroundStyle(HS.text3)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func replyCard(_ reply: Reply) -> some View {
        HSCard {
            HStack(spacing: 13) {
                Text(PartnerCopy.initial(partnerName))
                    .font(.hs(14, .semibold))
                    .foregroundStyle(HS.text2)
                    .frame(width: 34, height: 34)
                    .background(HS.raised)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.replyText(reply, spotName: trip.spot.name))
                        .font(.hs(15, .semibold))
                        .foregroundStyle(HS.text)
                    Text("\(partnerName) · \(clockAt(reply.ts))")
                        .font(.hs(13))
                        .foregroundStyle(HS.text3)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// The server may add a reply kind this build has never heard of. Render the raw text if
    /// there is any, then fall back to the kind string itself — never crash, never blank
    /// (ADDENDUM §B: the WRITE side is a closed enum, the READ side tolerates anything).
    static func replyText(_ reply: Reply, spotName: String) -> String {
        if !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return reply.text }
        switch ReplyKind(rawValue: reply.kind) {
        case .fiveMore: return "5 more min"
        case .takeYourTime: return "Take your time"
        case .atSpot: return "I'm at \(spotName)"
        case .custom, .none: return reply.kind
        }
    }

    private func lateButton(label: String, minutes: Int) -> some View {
        smallButton(label: label, tint: HS.text2) { await onRunningLate(minutes) }
    }

    private func smallButton(
        label: String,
        tint: Color,
        action: @escaping () async -> String?
    ) -> some View {
        Button { run(action) } label: {
            Text(label)
                .font(.hs(15, .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(HS.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(HS.line, lineWidth: 1)
                )
                .opacity(busy ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func toldRow(
        done: Bool,
        title: String,
        accentSuffix: String? = nil,
        trailing: String,
        accent: Color
    ) -> some View {
        HStack(spacing: 13) {
            if done {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 21, height: 21)
            } else {
                Circle()
                    .strokeBorder(accent == HS.headstart ? HS.headstartEdge : HS.line, lineWidth: 2)
                    .frame(width: 21, height: 21)
            }
            HStack(spacing: 0) {
                Text(title).font(.hs(16)).foregroundStyle(done ? HS.text : HS.text2)
                if let accentSuffix {
                    Text(accentSuffix).font(.hs(16)).foregroundStyle(HS.headstart)
                }
            }
            Spacer(minLength: 8)
            Text(trailing).font(.hsNum(14, .regular)).foregroundStyle(HS.text3)
        }
    }

    private func run(_ action: @escaping () async -> String?) {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task {
            errorText = await action()
            busy = false
        }
    }
}

// MARK: - Preview data
//
// Same rule as `SpotPreviewData`: `Trip` and `Reply` have only their Firestore mappers, so
// sample data goes in through the same dictionary the server would send. Not DEBUG-gated —
// `#Preview` bodies compile in every configuration.

enum TripPreviewData {

    static func trip(
        id: String = "trip1",
        state: String = "driving",
        etaSeconds: Int? = 1_080,
        approximate: Bool = false,
        leadTimeMin: Int = 3,
        spotName: String = "Office",
        alerts: [String: Any] = ["started": true],
        receiverView: [String: Any]? = ["etaSeconds": 1_080, "progressPct": 47],
        startedAt: Int64? = 1_700_000_000_000,
        routePolyline: String? = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
    ) -> Trip {
        var data: [String: Any] = [
            "pairId": "pair1",
            "driverUid": "uidA",
            "receiverUid": "uidB",
            "spotId": "s1",
            "spot": ["lat": 23.7806, "lng": 90.4193, "radiusM": 100, "name": spotName],
            "leadTimeMin": leadTimeMin,
            "state": state,
            "bands": ["far": 12_000, "near": 3_850, "lead": 900],
            "phaseHint": "far",
            "alerts": alerts,
            "createdAt": 1_700_000_000_000,
        ]
        if let etaSeconds {
            data["eta"] = ["seconds": etaSeconds, "updatedAt": 1_700_000_000_000, "approximate": approximate]
        }
        if let receiverView { data["receiverView"] = receiverView }
        if let startedAt { data["startedAt"] = startedAt }
        if let routePolyline { data["routePolyline"] = routePolyline }
        return Trip(id: id, data: data)!
    }

    /// Builds the server's `receiverView` projection. The nested server key it writes is
    /// deliberately spelled out HERE, in the Driver folder, and nowhere in `UI/Receiver/` — the
    /// receiver screens must survive `grep -rn 'lastPos' ios/Headstart/UI/Receiver/` returning
    /// nothing (CLIENT_CONTRACT_ADDENDUM.md §H), and preview fixtures are not an exemption.
    /// `point == nil` is fuzzy mode: the server simply omits it.
    static func receiverView(
        etaSeconds: Int,
        progressPct: Int,
        point: (lat: Double, lng: Double)? = nil
    ) -> [String: Any] {
        var data: [String: Any] = ["etaSeconds": etaSeconds, "progressPct": progressPct]
        if let point { data["lastPos"] = ["lat": point.lat, "lng": point.lng] }
        return data
    }

    static func reply(
        kind: String = "fiveMore",
        text: String = "5 more min",
        fromUid: String = "uidB",
        ts: Int64 = 1_700_000_400_000
    ) -> Reply {
        Reply(id: "r1", data: ["fromUid": fromUid, "kind": kind, "text": text, "ts": ts])!
    }
}

#Preview("Driver trip") {
    DriverTripView(
        trip: TripPreviewData.trip(),
        partnerName: "Sara",
        onRunningLate: { _ in nil },
        onCancel: { nil },
        onArrived: { nil }
    )
}

#Preview("Driver trip — late, replied, all alerts sent") {
    DriverTripView(
        trip: TripPreviewData.trip(
            etaSeconds: 240,
            approximate: true,
            alerts: ["started": true, "tenMin": true, "leadTime": true, "slipCount": 2]
        ),
        partnerName: "Sara",
        latestReply: TripPreviewData.reply(kind: "takeYourTime", text: "Take your time"),
        onRunningLate: { _ in nil },
        onCancel: { nil },
        onArrived: { nil }
    )
}

#Preview("Driver trip — unnamed partner, callable failed") {
    DriverTripView(
        trip: TripPreviewData.trip(),
        onRunningLate: { _ in HeadstartError.driverOnly.userMessage },
        onCancel: { HeadstartError.tripNotFound.userMessage },
        onArrived: { HeadstartError.offline.userMessage }
    )
}
