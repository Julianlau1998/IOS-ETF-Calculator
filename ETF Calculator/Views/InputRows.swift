//
//  InputRows.swift
//  ETF Calculator
//

import SwiftUI

/// The rounded value field shared by all input rows, so they line up.
private struct InputFieldStyle: ViewModifier {
    let isActive: Bool
    let tint: Color

    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 132

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: min(width, 200), alignment: .trailing)
            .background(.fill.tertiary, in: .rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isActive ? tint : .clear, lineWidth: 1.5)
            }
            .animation(.snappy(duration: 0.2), value: isActive)
    }
}

extension View {
    fileprivate func inputFieldStyle(isActive: Bool = false, tint: Color = .accentColor) -> some View {
        modifier(InputFieldStyle(isActive: isActive, tint: tint))
    }
}

/// A form row with a trailing numeric field and a unit (currency symbol, %, …).
/// The whole row is tappable and the value sits in a visible input field.
struct NumberInputRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    var unit: String
    var fractionDigits: ClosedRange<Int> = 0...2
    var systemImage: String?
    var color: Color = .accentColor
    /// Shows the unit before the number, e.g. "$" in "$10,000".
    var unitLeading = false

    @FocusState private var isFocused: Bool

    /// "7% p.a." in English, "7 % p.a." in German.
    private var unitSpacing: CGFloat {
        unit.hasPrefix("%") && !NumberStyle.percentHasSpace ? 1 : 4
    }

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                IconTile(systemImage: systemImage, color: color)
            }
            Text(title)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
            Spacer(minLength: 8)
            HStack(spacing: unitSpacing) {
                if unitLeading {
                    Text(unit)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                TextField(title, value: $value, format: .number.precision(.fractionLength(fractionDigits)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .fontWeight(.medium)
                    .focused($isFocused)
                    .onChange(of: value) { _, newValue in
                        // Negative amounts and rates make no sense in this calculator.
                        if newValue < 0 { value = 0 }
                    }
                if !unit.isEmpty, !unitLeading {
                    Text(unit)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .inputFieldStyle(isActive: isFocused, tint: color)
        }
        .contentShape(.rect)
        // Tapping anywhere on the row starts editing, not just the digits.
        .onTapGesture { isFocused = true }
    }
}

/// A currency amount row, showing the currency symbol of the selected currency.
struct CurrencyInputRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    var systemImage: String?
    var color: Color = .accentColor

    @Environment(\.currencyCode) private var currency

    var body: some View {
        NumberInputRow(
            title: title,
            value: $value,
            unit: Locale.current.currencySymbol(for: currency),
            systemImage: systemImage,
            color: color,
            unitLeading: NumberStyle.currencySymbolIsLeading(currency)
        )
    }
}

/// Duration in years: − / + inside the same field style as the other rows,
/// with a slim slider below for quick changes.
struct YearsInputRow: View {
    @Binding var years: Int
    var range: ClosedRange<Int> = SavingsPlan.yearsRange

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconTile(systemImage: "hourglass", color: .purple)
                Text("Duration")
                    .lineLimit(2)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    stepButton(systemImage: "minus", delta: -1)
                        .disabled(years <= range.lowerBound)
                    Text("^[\(years) Year](inflect: true)")
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.numericText(value: Double(years)))
                        .animation(.snappy, value: years)
                    stepButton(systemImage: "plus", delta: 1)
                        .disabled(years >= range.upperBound)
                }
                .padding(.horizontal, -6)
                .inputFieldStyle()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Duration")
                .accessibilityValue(Text("^[\(years) Year](inflect: true)"))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: years = min(range.upperBound, years + 1)
                    case .decrement: years = max(range.lowerBound, years - 1)
                    @unknown default: break
                    }
                }
            }
            Slider(
                value: Binding(get: { Double(years) }, set: { years = Int($0.rounded()) }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(.purple)
            .controlSize(.small)
            // Align with the row title next to the icon tile.
            .padding(.leading, 41)
            .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection, trigger: years)
    }

    private func stepButton(systemImage: String, delta: Int) -> some View {
        Button {
            years = min(range.upperBound, max(range.lowerBound, years + delta))
        } label: {
            Image(systemName: systemImage)
                .font(.footnote.weight(.bold))
                .frame(width: 28, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .buttonRepeatBehavior(.enabled)
    }
}

/// Shows a "Done" button in the navigation bar while the keyboard is up,
/// since number pads have no return key.
private struct KeyboardDoneButton: ViewModifier {
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.toolbar {
            if router.isKeyboardVisible {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) {
                        UIApplication.shared.dismissKeyboard()
                    }
                }
            }
        }
    }
}

extension View {
    func keyboardDoneButton() -> some View {
        modifier(KeyboardDoneButton())
    }
}

/// Quick picks for typical long-term return assumptions, as a tidy 2 × 2 grid.
struct ReturnPresets: View {
    @Binding var value: Double

    private let presets: [(title: LocalizedStringResource, rate: Double)] = [
        ("Cautious", 4),
        ("Balanced", 6),
        ("World ETF", 7),
        ("Optimistic", 9)
    ]

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(presets, id: \.rate) { preset in
                let isSelected = value == preset.rate
                Button {
                    withAnimation(.snappy) { value = preset.rate }
                } label: {
                    HStack(spacing: 4) {
                        Text(preset.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 2)
                        Text(verbatim: preset.rate.percentText())
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(
                        isSelected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.fill.tertiary),
                        in: .rect(cornerRadius: 10, style: .continuous)
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        // Align with the row title next to the icon tile.
        .padding(.leading, 41)
        .sensoryFeedback(.selection, trigger: value)
    }
}

/// Yearly special payment and an optional savings pause.
struct SpecialPaymentsSection: View {
    @Binding var plan: SavingsPlan

    private var isPauseEnabled: Binding<Bool> {
        Binding {
            plan.hasPause
        } set: { isOn in
            withAnimation(.snappy) {
                if isOn {
                    plan.pauseStartYear = min(max(1, plan.years / 2), plan.years)
                    plan.pauseLength = 1
                } else {
                    plan.pauseStartYear = 0
                    plan.pauseLength = 0
                }
            }
        }
    }

    var body: some View {
        Section {
            CurrencyInputRow(title: "Yearly Special Payment", value: $plan.yearlySpecialPayment, systemImage: "gift.fill", color: .mint)
            Toggle(isOn: isPauseEnabled) {
                HStack(spacing: 12) {
                    IconTile(systemImage: "pause.fill", color: .gray)
                    Text("Savings Pause")
                }
            }
            if plan.hasPause {
                Stepper(value: $plan.pauseStartYear, in: 1...max(1, plan.years)) {
                    LabeledContent("From Year") {
                        Text(verbatim: "\(plan.pauseStartYear)")
                            .monospacedDigit()
                    }
                }
                .padding(.leading, 41)
                Stepper(value: $plan.pauseLength, in: 1...max(1, plan.years)) {
                    LabeledContent("Duration") {
                        Text("^[\(plan.pauseLength) Year](inflect: true)")
                            .monospacedDigit()
                    }
                }
                .padding(.leading, 41)
            }
        } header: {
            Text("Special Payments & Pauses")
        } footer: {
            Text("Special payments are invested at the end of each year, e.g. a bonus. During a pause, no contributions are made — the portfolio keeps growing.")
        }
    }
}
