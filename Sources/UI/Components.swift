import SwiftUI

enum Theme {
    static let panelWidth: CGFloat = 316
    static let cardRadius: CGFloat = 9
    static let rowHeight: CGFloat = 22
    static let background = Color(red: 0.075, green: 0.078, blue: 0.086)
    static let cardFill = Color.white.opacity(0.04)
    static let cardStroke = Color.white.opacity(0.08)
    static let divider = Color.white.opacity(0.07)
    static let controlFill = Color.white.opacity(0.06)
    static let batteryGradient = Gradient(colors: [.red, .orange, .yellow, .green])
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(.secondary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 2)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            _VariadicView.Tree(DividedLayout()) { content }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.cardStroke))
    }
}

private struct DividedLayout: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        ForEach(children) { child in
            child.padding(.vertical, 3)
            if child.id != last { Rectangle().fill(Theme.divider).frame(height: 1) }
        }
    }
}

struct SettingRow<Control: View>: View {
    var icon: String?
    let title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 15)
            }
            Text(title).font(.system(size: 12)).lineLimit(1).fixedSize()
            Spacer(minLength: 8)
            control
        }
        .frame(minHeight: Theme.rowHeight)
    }
}

struct Pill: View {
    let text: String
    var icon: String?
    var dot = false
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            if dot { Circle().fill(color).frame(width: 5, height: 5) }
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}

// gradient spans the whole track, only the filled part is visible
struct BatteryBar: View {
    let level: Int

    var body: some View {
        GeometryReader { geo in
            let width = max(4, geo.size.width * CGFloat(min(max(level, 0), 100)) / 100)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                LinearGradient(gradient: Theme.batteryGradient, startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width)
                    .frame(width: width, alignment: .leading)
                    .clipShape(Capsule())
                    .shadow(color: tipColor.opacity(0.5), radius: 3)
            }
        }
        .frame(height: 5)
    }

    private var tipColor: Color {
        switch level {
        case ..<25: return .red
        case ..<50: return .orange
        case ..<75: return .yellow
        default: return .green
        }
    }
}

// commits on release. snaps by hand because step: draws tick marks
struct CommitSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let onCommit: (Double) -> Void
    @State private var draft: Double?

    var body: some View {
        Slider(value: Binding(get: { draft ?? value }, set: { draft = ($0 / step).rounded() * step }), in: range) { editing in
            if !editing, let d = draft, d != value { onCommit(d) }
        }
        .controlSize(.mini)
        .onChange(of: value) { _ in draft = nil }
    }
}

struct SegmentPicker<T: Hashable>: View {
    let options: [T]
    let selection: T?
    let label: (T) -> String
    let onSelect: (T) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                let selected = o == selection
                Button { if !selected { onSelect(o) } } label: {
                    Text(label(o))
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 6)
                        .frame(height: 17)
                        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color.white.opacity(0.16) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(1.5)
        .background(RoundedRectangle(cornerRadius: 6.5).fill(Theme.controlFill))
        .overlay(RoundedRectangle(cornerRadius: 6.5).strokeBorder(Theme.cardStroke))
    }
}

struct FooterButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(hover ? 0.1 : 0.05)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.cardStroke))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

extension RGB {
    var color: Color { Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }

    init?(_ color: Color) {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(r: UInt8((c.redComponent * 255).rounded()), g: UInt8((c.greenComponent * 255).rounded()),
                  b: UInt8((c.blueComponent * 255).rounded()))
    }

    init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: UInt8(v >> 16 & 0xFF), g: UInt8(v >> 8 & 0xFF), b: UInt8(v & 0xFF))
    }
}
