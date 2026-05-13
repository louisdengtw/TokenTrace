import SwiftUI

/// Range selector used by both Dashboard and Export sheet. Chip presets
/// (24h / 7d / 30d / All) live on the left; From/To `DatePicker`s on the right.
/// Editing either date deselects the chips and enters Custom state. From > To
/// is prevented interactively.
struct RangePickerView: View {
    @Binding var selection: RangeSelection

    /// `oldestSample` is only consulted to resolve the `.all` preset's From
    /// date for display purposes. Pass `nil` if not yet known.
    let oldestSample: Date?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            chipRow
            datePickers
        }
    }

    // MARK: - Chip row

    private var chipRow: some View {
        HStack(spacing: 0) {
            ForEach(RangePreset.allCases) { preset in
                chip(preset)
            }
        }
        .padding(1.5)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(scheme == .dark
                      ? Color.white.opacity(0.06)
                      : Color.black.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(scheme == .dark
                                ? Color.white.opacity(0.03)
                                : Color.black.opacity(0.04), lineWidth: 0.5)
                )
        )
    }

    private func chip(_ preset: RangePreset) -> some View {
        let isSelected = (selection == .preset(preset))
        return Button {
            selection = .preset(preset)
        } label: {
            Text(preset.label)
                .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelected ? .primary : Color.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(isSelected
                              ? (scheme == .dark
                                 ? Color.white.opacity(0.14)
                                 : Color.white.opacity(0.96))
                              : Color.clear)
                        .shadow(color: isSelected
                                ? Color.black.opacity(0.08) : .clear,
                                radius: 0.5, y: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date pickers

    private var datePickers: some View {
        let (resolvedFrom, resolvedTo) = selection.resolved(now: Date(), oldestSample: oldestSample)

        return HStack(spacing: 6) {
            DatePillButton(
                date: fromBinding(resolvedFrom: resolvedFrom, resolvedTo: resolvedTo),
                validRange: Date.distantPast...resolvedTo
            )

            Text("→")
                .foregroundStyle(.tertiary)
                .font(.system(size: 10, weight: .medium))

            DatePillButton(
                date: toBinding(resolvedFrom: resolvedFrom, resolvedTo: resolvedTo),
                validRange: resolvedFrom...Date.distantFuture
            )
        }
    }

    /// `From` binding. Reads the currently resolved start; writing it pins
    /// the selection to Custom and clamps `to` upward if the new from > to.
    private func fromBinding(resolvedFrom: Date, resolvedTo: Date) -> Binding<Date> {
        Binding(
            get: { resolvedFrom },
            set: { newValue in
                let clampedTo = max(resolvedTo, newValue)
                selection = .custom(from: newValue, to: clampedTo)
            }
        )
    }

    /// `To` binding. Symmetric: writing it clamps `from` downward if needed.
    private func toBinding(resolvedFrom: Date, resolvedTo: Date) -> Binding<Date> {
        Binding(
            get: { resolvedTo },
            set: { newValue in
                let clampedFrom = min(resolvedFrom, newValue)
                selection = .custom(from: clampedFrom, to: newValue)
            }
        )
    }
}
