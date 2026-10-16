import SwiftUI

// --snapshot out.png
@MainActor
func runSnapshot(_ args: [String]) -> Never {
    let i = args.firstIndex(of: "--snapshot")!
    let out = URL(fileURLWithPath: i + 1 < args.count ? args[i + 1] : "snapshot.png")
    let appearance = NSAppearance(named: args.contains("light") ? .aqua : .darkAqua)

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = KeyboardController()
    let host = NSHostingView(rootView: PanelView(controller: controller)
        .background(VisualEffect()))
    let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = appearance
    window.contentView = host
    window.setContentSize(host.fittingSize)
    window.orderFront(nil)

    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: out)
            print("saved \(out.path)")
            exit(0)
        }
    }
    app.run()
    exit(0)
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
