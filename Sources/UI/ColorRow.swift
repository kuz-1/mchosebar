import SwiftUI

struct ColorRow: View {
    let color: RGB
    let isMulti: Bool
    let multiAvailable: Bool
    let onColor: (RGB) -> Void
    let onMulti: (Bool) -> Void

    @State private var hexDraft = ""
    @State private var editingHex = false
    @State private var showPicker = false
    @FocusState private var hexFocused: Bool

    var body: some View {
        SettingRow(title: "Color") {
            HStack(spacing: 6) {
                TextField("", text: Binding(get: { editingHex ? hexDraft : color.hex }, set: { hexDraft = $0; editingHex = true }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 60)
                    .focused($hexFocused)
                    .onSubmit(commitHex)
                    .onChange(of: hexFocused) { focused in if !focused { commitHex() } }
                Button { showPicker.toggle() } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.white.opacity(0.25)))
                        .shadow(color: color.color.opacity(0.8), radius: 4)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                    ColorPickerPopover(current: color) { onColor($0) }
                }
            }
            .padding(.leading, 7)
            .padding(.trailing, 4)
            .frame(height: 21)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.controlFill))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.cardStroke))
            .opacity(isMulti ? 0.45 : 1)
            .help(isMulti ? "Multi uses the effect's own colors; picking a color switches to single" : "")

            if multiAvailable {
                Button { onMulti(!isMulti) } label: {
                    Text("Multi")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .frame(height: 19)
                        .foregroundStyle(isMulti ? Color.white : Color.primary)
                        .background(Capsule().fill(isMulti ? Color.accentColor : Theme.controlFill))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func commitHex() {
        defer { editingHex = false }
        guard editingHex, let c = RGB(hex: hexDraft), c != color else { return }
        onColor(c)
    }
}

struct ColorPickerPopover: View {
    let current: RGB
    let onPick: (RGB) -> Void
    @State private var custom: Color = .white
    @State private var pending: DispatchWorkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 4), spacing: 8) {
                ForEach(RGB.presets, id: \.color) { preset in
                    Button { onPick(preset.color) } label: {
                        Circle()
                            .fill(preset.color.color)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(preset.color == current ? 0.9 : 0.15),
                                                           lineWidth: preset.color == current ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                }
            }
            Divider()
            HStack {
                Text("Custom").font(.system(size: 12))
                Spacer()
                ColorPicker("", selection: $custom, supportsOpacity: false).labelsHidden()
            }
        }
        .padding(12)
        .frame(width: 160)
        .onAppear { custom = current.color }
        .onChange(of: custom) { c in
            // color panel fires while dragging, only send the last one
            pending?.cancel()
            let work = DispatchWorkItem { if let rgb = RGB(c), rgb != current { onPick(rgb) } }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }
}
