import SwiftUI

/// Soft, borderless pill button style. Two visual variants:
///   - `.standard`  : subtle fill, used for most actions
///   - `.prominent` : accent fill, used for the primary call-to-action
///
/// Replaces SwiftUI's stock `.bordered` / `.borderedProminent` which look
/// generic and don't match the rest of TokenTrace's chrome.
struct PillButtonStyle: ButtonStyle {
    enum Variant { case standard, prominent }
    enum Size    { case small, regular }

    var variant: Variant = .standard
    var size: Size = .small

    @Environment(\.colorScheme) private var scheme
    @State private var hovering: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(textColor(pressed: configuration.isPressed))
            .padding(.horizontal, hPadding)
            .padding(.vertical, vPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed, hovering: hovering))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    // MARK: - Geometry

    private var hPadding: CGFloat {
        switch size {
        case .small:   return 10
        case .regular: return 12
        }
    }

    private var vPadding: CGFloat {
        switch size {
        case .small:   return 4
        case .regular: return 5
        }
    }

    private var cornerRadius: CGFloat {
        6
    }

    private var font: Font {
        switch size {
        case .small:   return .system(size: 11, weight: .medium)
        case .regular: return .system(size: 11.5, weight: .semibold)
        }
    }

    // MARK: - Color

    private func textColor(pressed: Bool) -> Color {
        switch variant {
        case .prominent:
            return .white
        case .standard:
            return pressed ? .secondary : .primary
        }
    }

    private func fill(pressed: Bool, hovering: Bool) -> Color {
        switch variant {
        case .prominent:
            let base = Color.accentColor
            if pressed  { return base.opacity(0.82) }
            if hovering { return base.opacity(0.95) }
            return base.opacity(0.90)
        case .standard:
            let bgOpacity: Double = {
                if scheme == .dark {
                    if pressed  { return 0.06 }
                    if hovering { return 0.14 }
                    return 0.09
                } else {
                    if pressed  { return 0.04 }
                    if hovering { return 0.09 }
                    return 0.06
                }
            }()
            return scheme == .dark
                ? Color.white.opacity(bgOpacity)
                : Color.black.opacity(bgOpacity)
        }
    }

    private var strokeColor: Color {
        switch variant {
        case .prominent:
            return .clear
        case .standard:
            return scheme == .dark
                ? Color.white.opacity(0.06)
                : Color.black.opacity(0.06)
        }
    }
}

// MARK: - Date pill

/// Borderless date trigger. Tap → reveals a `.graphical` calendar popover.
/// Replaces SwiftUI's `.compact` DatePicker, whose stock chrome (±-stepper
/// widgets, separators between the segments) feels out of place next to
/// custom-styled controls.
struct DatePillButton: View {
    @Binding var date: Date

    /// Allowed range. The graphical DatePicker enforces this visually too.
    let validRange: ClosedRange<Date>

    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(date, format: .dateTime.year().month(.abbreviated).day())
                    .monospacedDigit()
            }
        }
        .buttonStyle(PillButtonStyle(variant: .standard, size: .small))
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            DatePicker(
                "",
                selection: $date,
                in: validRange,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(12)
            .frame(width: 280)
        }
    }
}
