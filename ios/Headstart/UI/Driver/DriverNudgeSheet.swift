// ios/Headstart/UI/Driver/DriverNudgeSheet.swift
import SwiftUI

/// `design/DriverNudge.dc.html`. Raised when the server sets `trip.alerts.didYouLeave`, which
/// it does after three minutes with no movement of 150 m, and delivered as the `didYouLeave`
/// push (CLIENT_CONTRACT.md §Push payloads).
///
/// The receiver has been told NOTHING. That last line is load-bearing — it is the difference
/// between a nudge and an accusation — so it stays, and nothing on this sheet notifies anyone.
/// "I'm on my way now" simply dismisses; the trip keeps running and the next position upload is
/// what tells the server the driver moved.
public struct DriverNudgeSheet: View {

    @State private var busy = false
    @State private var errorText: String?

    private let partnerName: String
    private let onOnMyWay: () -> Void
    private let onCancelTrip: () async -> String?

    public init(
        partnerName: String = PartnerName.fallback,
        onOnMyWay: @escaping () -> Void,
        onCancelTrip: @escaping () async -> String?
    ) {
        self.partnerName = partnerName
        self.onOnMyWay = onOnMyWay
        self.onCancelTrip = onCancelTrip
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Capsule()
                .fill(HS.line)
                .frame(width: 44, height: 5)
                .frame(maxWidth: .infinity)

            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(HS.headstart)
                .frame(width: 52, height: 52)
                .background(HS.headstartIconWash)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 11) {
                Text("Did you actually leave?")
                    .font(.hs(27, .bold))
                    .tracking(-0.9)
                    .foregroundStyle(HS.text)
                Text("You tapped \"I'm coming\" three minutes ago but haven't moved. \(partnerName) is counting on this being real.")
                    .font(.hs(16))
                    .lineSpacing(4)
                    .foregroundStyle(HS.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorText {
                Text(errorText)
                    .font(.hs(14))
                    .foregroundStyle(HS.delayed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 11) {
                HSButton("I'm on my way now", enabled: !busy, action: onOnMyWay)
                Button {
                    guard !busy else { return }
                    busy = true
                    errorText = nil
                    Task {
                        errorText = await onCancelTrip()
                        busy = false
                    }
                } label: {
                    Text("Cancel the trip")
                        .font(.hs(17, .medium))
                        .foregroundStyle(HS.delayed)
                        .frame(maxWidth: .infinity)
                        .frame(height: HS.controlHeight)
                        .background(HS.raised)
                        .clipShape(RoundedRectangle(cornerRadius: HS.Radius.control, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: HS.Radius.control, style: .continuous)
                                .strokeBorder(HS.line, lineWidth: 1)
                        )
                        .opacity(busy ? 0.6 : 1)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }

            Text("\(partnerName) hasn't been told anything is wrong.")
                .font(.hs(13))
                .lineSpacing(3)
                .foregroundStyle(HS.text3)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, HS.screenPadding)
        .padding(.top, 14)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity)
        .background(HS.card)
        .presentationDetents([.height(490)])
        .presentationCornerRadius(HS.Radius.sheet)
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
    }
}

#Preview("Driver nudge") {
    Color.black.sheet(isPresented: .constant(true)) {
        DriverNudgeSheet(partnerName: "Sara", onOnMyWay: {}, onCancelTrip: { nil })
    }
}

#Preview("Driver nudge — unnamed partner, cancel failed") {
    Color.black.sheet(isPresented: .constant(true)) {
        DriverNudgeSheet(onOnMyWay: {}, onCancelTrip: { HeadstartError.tripNotFound.userMessage })
    }
}
