// ios/HeadstartWidget/HeadstartWidgetBundle.swift
//
// M1 ships ONE widget and it is not a Home Screen widget: `TripLiveActivity` is an
// `ActivityConfiguration`, the receiver's Lock Screen / Dynamic Island countdown. The
// Xcode template's timeline widget and control widget are deliberately absent — nothing
// in the product wants a static tile.
//
// The target itself, its bundle id (`com.mutexdev.headstart.HeadstartWidget`), its
// Info.plist, its `UIAppFonts` and the files it shares with the app (Theme/,
// HeadstartActivityAttributes.swift) are all declared in ios/project.yml. Adding a file to
// this extension means adding it to that `sources:` list — never by ticking a Target
// Membership checkbox, which no automated pipeline can reach.
import SwiftUI
import WidgetKit

@main
struct HeadstartWidgetBundle: WidgetBundle {
    var body: some Widget {
        TripLiveActivity()
    }
}
