import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Helpers

func formatBytes(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}

@MainActor
func chooseFiles(types: [UTType] = [], multiple: Bool = true) -> [URL] {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = multiple
    if !types.isEmpty { panel.allowedContentTypes = types }
    return panel.runModal() == .OK ? panel.urls : []
}

@MainActor
func chooseFolder(prompt: String = "Choose") -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.prompt = prompt
    return panel.runModal() == .OK ? panel.url : nil
}

@MainActor
func chooseSaveLocation(name: String, type: UTType) -> URL? {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    panel.allowedContentTypes = [type]
    return panel.runModal() == .OK ? panel.url : nil
}

// MARK: - Buttons

/// Capsule button: `.filled` is solid ink, `.outlined` is a thin line.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case filled, outlined }
    var kind: Kind = .outlined
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mono(compact ? 11 : 13, .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(kind == .filled ? Theme.bg : Theme.ink)
            .padding(.horizontal, compact ? 14 : 22)
            .padding(.vertical, compact ? 7 : 12)
            .background(Capsule().fill(kind == .filled ? Theme.ink : Color.clear))
            .overlay(Capsule().stroke(Theme.ink, lineWidth: 1.2))
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.3)
            .contentShape(Capsule())
    }
}

/// Small round icon-only button.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 34
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Theme.ink.opacity(0.6), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.3)
            .contentShape(Circle())
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static func pill(_ kind: PillButtonStyle.Kind, compact: Bool = false) -> PillButtonStyle {
        PillButtonStyle(kind: kind, compact: compact)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var roundIcon: IconButtonStyle { IconButtonStyle() }
}

// MARK: - Toggles

/// Outlined pill switch. The whole row (switch + label) is one big button, at least 36pt tall.
struct PillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? Theme.ink : Theme.card)
                    Capsule().stroke(Theme.ink, lineWidth: 1.4)
                    Circle().fill(configuration.isOn ? Theme.bg : Theme.ink).frame(width: 18, height: 18).padding(3)
                }
                .frame(width: 50, height: 26)
                configuration.label
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "on" : "off")
    }
}

/// Rounded square checkbox. The whole row is one big button.
struct CheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(configuration.isOn ? Theme.ink : Theme.card)
                    RoundedRectangle(cornerRadius: 6).stroke(Theme.ink, lineWidth: 1.4)
                    if configuration.isOn {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.bg)
                    }
                }
                .frame(width: 22, height: 22)
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "ticked" : "unticked")
    }
}

extension ToggleStyle where Self == PillToggleStyle { static var pill: PillToggleStyle { PillToggleStyle() } }
extension ToggleStyle where Self == CheckToggleStyle { static var check: CheckToggleStyle { CheckToggleStyle() } }

// MARK: - Light / dark switch

/// Sun and moon on an outlined pill; the filled knob sits on the active one.
struct ThemeSwitch: View {
    @Binding var isDark: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { isDark.toggle() }
        } label: {
            ZStack(alignment: isDark ? .trailing : .leading) {
                Capsule().stroke(Theme.ink, lineWidth: 1.2)
                HStack(spacing: 0) {
                    Image(systemName: "sun.max").frame(width: 38)
                    Image(systemName: "moon").frame(width: 38)
                }
                .font(.system(size: 13))
                Capsule().fill(Theme.ink)
                    .frame(width: 34, height: 26)
                    .overlay(Image(systemName: isDark ? "moon.fill" : "sun.max.fill").font(.system(size: 13)).foregroundStyle(Theme.bg))
                    .padding(3)
            }
            .frame(width: 76, height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isDark ? "Switch to light mode" : "Switch to dark mode")
        .accessibilityLabel(isDark ? "Dark mode on" : "Light mode on")
    }
}

// MARK: - Segmented control and dropdown

struct PillSegmented<T: Hashable>: View {
    @Binding var selection: T
    var options: [(T, String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let selected = selection == options[i].0
                Button { selection = options[i].0 } label: {
                    Text(options[i].1)
                        .font(.mono(12, .semibold)).textCase(.uppercase).tracking(0.5)
                        .foregroundStyle(selected ? Theme.bg : Theme.ink)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Capsule().fill(selected ? Theme.ink : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .overlay(Capsule().stroke(Theme.ink, lineWidth: 1.2))
        .fixedSize()
    }
}

/// Outlined dropdown, like "SOLAR PANELS ⌄" in the reference.
struct PillPicker<T: Hashable>: View {
    @Binding var selection: T
    var options: [(T, String)]
    var minWidth: CGFloat = 0

    private var title: String { options.first { $0.0 == selection }?.1 ?? "" }

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { i in
                Button(options[i].1) { selection = options[i].0 }
            }
        } label: {
            HStack(spacing: 10) {
                Text(title).font(.mono(12, .semibold)).textCase(.uppercase).tracking(0.5)
                Spacer(minLength: 6)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .frame(minWidth: minWidth)
            .overlay(Capsule().stroke(Theme.ink, lineWidth: 1.2))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
    }
}

// MARK: - Cards and layout

/// Big rounded outlined panel with an icon and an uppercase title.
struct Card<Content: View>: View {
    var title: String?
    var icon: String?
    /// true: the card (outline included) grows to fill the height it is given, so neighbouring cards line up.
    var fill = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                HStack(spacing: 8) {
                    if let icon { Image(systemName: icon).font(.system(size: 14, weight: .regular)) }
                    Text(title).font(.mono(14, .semibold)).textCase(.uppercase).tracking(1)
                    Spacer()
                }
            }
            content
        }
        // When the card stretches, its content stretches too, so a Spacer can pin a button to the bottom edge.
        .frame(maxHeight: fill ? .infinity : nil, alignment: .top)
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.ink.opacity(0.85), lineWidth: 1))
    }
}

struct TwoColumns<L: View, R: View>: View {
    /// true: both columns become as tall as the taller one (a flexible card inside stretches to fill).
    var stretch = false
    @ViewBuilder var left: L
    @ViewBuilder var right: R

    var body: some View {
        let row = HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) { left }.frame(maxWidth: .infinity)
            VStack(spacing: 20) { right }.frame(maxWidth: .infinity)
        }
        if stretch { row.fixedSize(horizontal: false, vertical: true) } else { row }
    }
}

private struct PreviewModeKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True only while rendering design previews to PNG (ImageRenderer cannot draw scroll views).
    var previewMode: Bool {
        get { self[PreviewModeKey.self] }
        set { self[PreviewModeKey.self] = newValue }
    }
}

/// A ScrollView that steps aside in preview mode.
struct AdaptiveScroll<Content: View>: View {
    @Environment(\.previewMode) private var previewMode
    /// Scrolls the view with this id into sight whenever `tick` changes.
    var scrollTo: (id: String, tick: Int)? = nil
    @ViewBuilder var content: Content
    var body: some View {
        if previewMode {
            content
        } else {
            ScrollViewReader { proxy in
                ScrollView { content }
                    .scrollIndicators(.hidden)
                    .onChange(of: scrollTo?.tick) { _, _ in
                        if let id = scrollTo?.id { withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .bottom) } }
                    }
            }
        }
    }
}

/// Scrollable page body shared by every section.
struct PageScroll<Content: View>: View {
    var scrollTo: (id: String, tick: Int)? = nil
    @ViewBuilder var content: Content
    var body: some View {
        AdaptiveScroll(scrollTo: scrollTo) {
            VStack(spacing: 20) { content }
                .padding(.top, 22).padding(.bottom, 32)
        }
    }
}

struct StatusLine: View {
    var text: String?
    var isError = false
    var body: some View {
        if let text {
            Label {
                Text(text).textSelection(.enabled)
            } icon: {
                Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
            }
            .font(.mono(13))
            .foregroundStyle(isError ? Theme.warn : Theme.mute)
        }
    }
}

/// Small grey explanation text.
struct Hint: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.mono(12)).foregroundStyle(Theme.mute).fixedSize(horizontal: false, vertical: true) }
}

/// Thin outlined search / text input.
struct PillField: View {
    var placeholder: String
    @Binding var text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).foregroundStyle(Theme.mute) }
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.mono(12))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .overlay(Capsule().stroke(Theme.ink, lineWidth: 1.2))
    }
}

// MARK: - Drop zone

struct DropZone: View {
    var title: String
    var subtitle: String
    var systemImage = "square.and.arrow.down"
    var types: [UTType] = []
    var multiple = true
    /// Once something is picked, shrink the big tile to a slim bar (it still takes drops and clicks).
    var compact = false
    var compactTitle = "Drop more, or click to choose"
    var onFiles: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        // The whole box is one button: click anywhere to choose, or drop files on it.
        Button {
            let urls = chooseFiles(types: types, multiple: multiple)
            if !urls.isEmpty { onFiles(urls) }
        } label: {
            if compact { compactLabel } else { fullLabel }
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            onFiles(multiple ? files : Array(files.prefix(1)))
            return true
        } isTargeted: { targeted = $0 }
    }

    private var compactLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .light))
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Theme.ink, lineWidth: 1.2))
            Text(compactTitle).font(.mono(11, .semibold)).textCase(.uppercase).tracking(0.6).lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "folder").font(.system(size: 13, weight: .regular))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 5]))
                .foregroundStyle(targeted ? Theme.ink : Theme.mute)
                .background(targeted ? Theme.ink.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var fullLabel: some View {
        Group {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .light))
                    .frame(width: 54, height: 54)
                    .overlay(Circle().stroke(Theme.ink, lineWidth: 1.2))
                Text(title).font(.mono(14, .semibold)).textCase(.uppercase).tracking(0.8)
                Text(subtitle).font(.mono(12)).foregroundStyle(Theme.mute).multilineTextAlignment(.center)
                Label("Click to choose", systemImage: "folder")
                    .font(.mono(11, .semibold)).textCase(.uppercase).tracking(0.6)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .overlay(Capsule().stroke(Theme.ink, lineWidth: 1.2))
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 5]))
                    .foregroundStyle(targeted ? Theme.ink : Theme.mute)
                    .background(targeted ? Theme.ink.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

/// A picked picture, centred, never taller than `maxHeight`, with a cross to take it out again.
struct PickedPreview: View {
    var image: NSImage
    var maxHeight: CGFloat = 240
    var onRemove: (() -> Void)?

    var body: some View {
        let ratio = max(0.2, min(5, image.size.width / max(image.size.height, 1)))
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay { Image(nsImage: image).resizable().scaledToFill() }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.ink.opacity(0.25), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if let onRemove {
                    Button(action: onRemove) { Image(systemName: "xmark") }
                        .buttonStyle(IconButtonStyle(size: 30))
                        .background(Circle().fill(Theme.card))
                        .padding(10)
                        .help("Remove this image")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: maxHeight)
    }
}

// MARK: - Tick dial (the round gauge from the reference)

struct TickDial: View {
    var value: String
    var caption: String
    var detail: String
    /// 0...1: where the little dot sits on the ring.
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(0..<60, id: \.self) { i in
                    let major = i % 5 == 0
                    Capsule().fill(Theme.ink)
                        .frame(width: major ? 2.2 : 1.6, height: major ? 15 : 8)
                        .offset(y: -(size / 2 - 11))
                        .rotationEffect(.degrees(Double(i) * 6))
                }
                Circle().stroke(Theme.ink, lineWidth: 1.2).frame(width: size * 0.74, height: size * 0.74)
                Circle().fill(Theme.ink).frame(width: 11, height: 11)
                    .offset(y: -(size * 0.435 - 9.5))   // halfway between the inner circle and the ticks
                    .rotationEffect(.degrees(max(0, min(progress, 1)) * 360))
                VStack(spacing: 4) {
                    Text(value).font(.mono(size * 0.2, .regular)).minimumScaleFactor(0.5).lineLimit(1)
                    Text(caption).font(.mono(12, .medium)).textCase(.uppercase).tracking(1)
                    Text(detail).font(.mono(11)).foregroundStyle(Theme.mute).lineLimit(1)
                }
                .frame(width: size * 0.62)
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Thin bar chart (the analytics chart from the reference)

struct ThinBars: View {
    struct Item: Identifiable { let id: String; let label: String; let value: Int }
    var items: [Item]

    var body: some View {
        let maxValue = max(items.map(\.value).max() ?? 1, 1)
        let top = Self.niceTop(maxValue)
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                // y axis
                VStack(alignment: .trailing) {
                    Text("\(top)"); Spacer(); Text("\(top / 2)"); Spacer(); Text("0")
                }
                .font(.mono(9)).foregroundStyle(Theme.mute).frame(width: 34, height: 140)

                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle().fill(Theme.ink.opacity(0.25)).frame(height: 1)
                            Spacer()
                        }
                    }
                    .frame(height: 140)
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(items) { item in
                            VStack(spacing: 3) {
                                Spacer(minLength: 0)
                                Text("\(item.value)").font(.mono(9)).foregroundStyle(Theme.mute)
                                Rectangle().fill(Theme.ink)
                                    .frame(width: 5, height: max(3, 120 * CGFloat(item.value) / CGFloat(top)))
                            }
                            .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 140)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Color.clear.frame(width: 34, height: 1)
                HStack(spacing: 0) {
                    ForEach(items) { item in
                        Text(item.label).font(.mono(9, .medium)).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    static func niceTop(_ v: Int) -> Int {
        let steps = [4, 10, 20, 50, 100, 200, 400, 500, 1000, 2000, 5000, 10000]
        return steps.first { $0 >= v } ?? v
    }
}

// MARK: - Settings row & category art

/// "LABEL   [control]" line used in settings cards.
struct SettingRow<Control: View>: View {
    var label: String
    @ViewBuilder var control: Control
    var body: some View {
        HStack(spacing: 14) {
            Text(label).font(.mono(12, .medium)).textCase(.uppercase).tracking(0.6)
                .foregroundStyle(Theme.mute).frame(width: 90, alignment: .leading)
            control
            Spacer(minLength: 0)
        }
    }
}

struct HairlineDivider: View {
    var body: some View { Rectangle().fill(Theme.ink.opacity(0.18)).frame(height: 1) }
}


/// Thin outlined progress bar. `fraction` 0...1, or nil for "working, no idea how long".
struct ProgressBar: View {
    var fraction: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.08))
                if let fraction {
                    Capsule().fill(Theme.ink)
                        .frame(width: max(14, geo.size.width * min(max(fraction, 0), 1)))
                        .animation(.easeOut(duration: 0.25), value: fraction)
                } else {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        Capsule().fill(Theme.ink)
                            .frame(width: geo.size.width * 0.3)
                            .offset(x: geo.size.width * 0.7 * abs(sin(phase * .pi)))
                    }
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.ink, lineWidth: 1.2))
        }
        .frame(height: 14)
    }
}

/// "Converting 3 of 12…" with a bar and an optional Cancel button. `fraction` nil = no known length.
struct WorkProgress: View {
    var title: String
    var fraction: Double?
    var onCancel: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.mono(13, .semibold))
                Spacer()
                if let onCancel {
                    Button(action: onCancel) { Label("Cancel", systemImage: "xmark") }
                        .buttonStyle(.pill(.outlined, compact: true))
                }
            }
            ProgressBar(fraction: fraction)
        }
        .padding(.vertical, 6)
    }
}

/// Black "Done" pill with a tick that stands in for the action button for a moment after it finishes.
struct DonePill: View {
    var title = "Done"
    @State private var bounce = false

    var body: some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(.mono(13, .semibold)).textCase(.uppercase).tracking(0.6)
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Capsule().fill(Theme.ink))
            .symbolEffect(.bounce, value: bounce)
            .onAppear { bounce.toggle() }
    }
}
