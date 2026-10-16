import SwiftUI

// debug: open -n build/MchoseBar.app --args --dump | --read 49 | --selftest
@main
enum Entry {
    static func main() {
        MainActor.assumeIsolated {
            let args = CommandLine.arguments
            if args.contains("--snapshot") { runSnapshot(args) }
            if args.contains("--dump") || args.contains("--read") || args.contains("--selftest") {
                runCLI(args)
            }
            MchoseBarApp.main()
        }
    }
}

struct MchoseBarApp: App {
    @StateObject private var controller = KeyboardController()

    var body: some Scene {
        MenuBarExtra {
            PanelView(controller: controller)
        } label: {
            MenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var controller: KeyboardController

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "keyboard")
            if !controller.isConnected {
                Text("✕")
            } else if let b = controller.battery {
                Text("\(b.level)%" + (b.isCharging ? "⚡︎" : ""))
            }
        }
    }
}
