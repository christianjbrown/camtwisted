import AppKit
import CamTwistControl
import SwiftUI

/// The About item of the app menu, which opens the About window.
struct AboutCommands: Commands {
    let details: AboutDetails

    var body: some Commands {
        CommandGroup(replacing: .appInfo) { OpenAboutButton(name: details.name) }
    }
}

private struct OpenAboutButton: View {
    @Environment(\.openWindow) private var openWindow
    let name: String

    var body: some View {
        Button("About \(name)") { openWindow(id: AboutView.windowIdentifier) }
    }
}

/// Keeps the window it sits in from being reopened at the next launch:
/// nobody wants to be greeted by the About window.
private struct ForgottenWindow: NSViewRepresentable {
    private final class Marker: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isRestorable = false
        }
    }

    func makeNSView(context: Context) -> NSView { Marker() }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// Shows the pointing hand while the mouse is over a link, the way a web
/// page does, so it reads as something to click.
private struct LinkCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { isOver in
            if isOver {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

/// Who made the app, where to get help, and what it was inspired by.
struct AboutView: View {
    static let windowIdentifier = "about"

    private enum Layout {
        static let width: CGFloat = 340
        static let iconSize: CGFloat = 96
        static let spacing: CGFloat = 14
        static let tightSpacing: CGFloat = 4
        static let padding: CGFloat = 24
    }

    /// What the window's own links and labels say.
    private enum Wording {
        static let support = "Help, bugs and ideas"
        static let madeBy = "Made by"
    }

    let details: AboutDetails

    var body: some View {
        VStack(spacing: Layout.spacing) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .accessibilityHidden(true)
            VStack(spacing: Layout.tightSpacing) {
                Text(details.name).font(.title2.bold())
                Text(details.versionLine).font(.callout).foregroundStyle(.secondary)
            }
            VStack(spacing: Layout.tightSpacing) {
                if !details.maker.isEmpty { Text("\(Wording.madeBy) \(details.maker)") }
                if let support = details.supportAddress { link(Wording.support, to: support) }
            }
            Divider()
            VStack(spacing: Layout.tightSpacing) {
                // A line each, so they stay balanced however the window is sized.
                ForEach(details.inspiration, id: \.self) { Text($0) }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Text(details.copyright).font(.footnote).foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(Layout.padding)
        .frame(width: Layout.width)
        .background(ForgottenWindow())
    }

    private func link(_ title: String, to address: URL) -> some View {
        Link(title, destination: address).modifier(LinkCursor())
    }
}
