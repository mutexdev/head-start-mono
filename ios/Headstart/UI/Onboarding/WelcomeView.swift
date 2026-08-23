// ios/Headstart/UI/Onboarding/WelcomeView.swift
import SwiftUI

/// `design/Welcome.dc.html`.
///
/// Every screen in this batch is a STATELESS `View`: it takes the data it renders and the
/// closures it calls, and it references no repository and no navigation state. `AppViewModel`
/// (a later batch) owns every stream and every route. That is what lets a screen be written,
/// previewed and reviewed before the flow that hosts it exists.
public struct WelcomeView: View {

    private let onGetStarted: () -> Void
    private let onHaveCode: () -> Void

    public init(onGetStarted: @escaping () -> Void, onHaveCode: @escaping () -> Void) {
        self.onGetStarted = onGetStarted
        self.onHaveCode = onHaveCode
    }

    public var body: some View {
        HSScreen {
            Spacer().frame(height: 34)

            HStack(spacing: 11) {
                HeadstartMark(size: 30)
                Text("Headstart")
                    .font(.hs(21, .bold))
                    .tracking(-0.6)
                    .foregroundStyle(HS.text)
            }

            Spacer().frame(height: 52)

            Text("Know exactly\nwhen to walk out.")
                .font(.hs(38, .bold))
                .tracking(-1.5)
                .lineSpacing(2)
                .foregroundStyle(HS.text)

            Spacer().frame(height: 18)

            Text("Your ride tells you when to leave the building — down to the minute you asked for.")
                .font(.hs(16))
                .lineSpacing(4)
                .foregroundStyle(HS.text2)

            Spacer().frame(height: 44)

            // The alert ladder, in the order the server fires it: started -> tenMin ->
            // leadTime -> arrived. Nothing here is live; it is the promise, drawn.
            VStack(alignment: .leading, spacing: 0) {
                timelineRow(
                    dot: HS.go, big: false, connector: true,
                    title: "Mostafi started driving", titleColor: HS.text, titleSize: 16,
                    subtitle: "ETA 22 min to Office", subtitleColor: HS.text3
                )
                timelineRow(
                    dot: HS.go, big: false, connector: true,
                    title: "10 minutes away", titleColor: HS.text, titleSize: 16,
                    subtitle: "wrap up what you're doing", subtitleColor: HS.text3
                )
                timelineRow(
                    dot: HS.headstart, big: true, connector: true,
                    title: "Start walking now", titleColor: HS.headstart, titleSize: 18,
                    subtitle: "the 3 minutes you asked for", subtitleColor: HS.text2
                )
                timelineRow(
                    dot: HS.line, big: false, connector: false,
                    title: "Arrived — tracking stops", titleColor: HS.text3, titleSize: 16,
                    subtitle: nil, subtitleColor: HS.text3
                )
            }

            Spacer()

            VStack(spacing: 12) {
                HSButton("Get started", action: onGetStarted)
                HSButton("I have an invite code", kind: .secondary, action: onHaveCode)
            }
            .padding(.bottom, 38)
        }
    }

    private func timelineRow(
        dot: Color, big: Bool, connector: Bool,
        title: String, titleColor: Color, titleSize: CGFloat,
        subtitle: String?, subtitleColor: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                Circle()
                    .fill(dot)
                    .frame(width: big ? 15 : 11, height: big ? 15 : 11)
                    .padding(.top, big ? 3 : 5)
                    .overlay(
                        Circle()
                            .stroke(HS.headstart.opacity(big ? 0.16 : 0), lineWidth: 5)
                            .frame(width: big ? 25 : 0, height: big ? 25 : 0)
                            .padding(.top, 3)
                    )
                if connector {
                    Rectangle().fill(HS.line).frame(width: 2)
                }
            }
            .frame(width: 15)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.hs(titleSize, big ? .bold : .semibold))
                    .foregroundStyle(titleColor)
                if let subtitle {
                    Text(subtitle).font(.hs(14)).foregroundStyle(subtitleColor)
                }
            }
            .padding(.bottom, connector ? 22 : 0)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The three-chevron mark from the artboards, drawn rather than shipped as an asset so it
/// inherits the palette. Real app-icon assets are M4.
public struct HeadstartMark: View {
    private let size: CGFloat
    public init(size: CGFloat) { self.size = size }

    public var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 32
            context.fill(
                Path(ellipseIn: CGRect(x: 3.3 * s, y: 12.8 * s, width: 6.4 * s, height: 6.4 * s)),
                with: .color(HS.go)
            )
            var chevron = Path()
            chevron.move(to: CGPoint(x: 14 * s, y: 9 * s))
            chevron.addLine(to: CGPoint(x: 21 * s, y: 16 * s))
            chevron.addLine(to: CGPoint(x: 14 * s, y: 23 * s))
            context.stroke(
                chevron,
                with: .color(HS.go),
                style: StrokeStyle(lineWidth: 3.2 * s, lineCap: .round, lineJoin: .round)
            )

            var faint = Path()
            faint.move(to: CGPoint(x: 23 * s, y: 9 * s))
            faint.addLine(to: CGPoint(x: 26.5 * s, y: 16 * s))
            faint.addLine(to: CGPoint(x: 23 * s, y: 23 * s))
            context.stroke(
                faint,
                with: .color(HS.go.opacity(0.35)),
                style: StrokeStyle(lineWidth: 3.2 * s, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview("Welcome") {
    WelcomeView(onGetStarted: {}, onHaveCode: {})
}
