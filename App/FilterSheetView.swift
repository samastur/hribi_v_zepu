import SwiftUI
import HikeKit

struct FilterSheetView: View {
    let walkingBounds: ClosedRange<Int>?
    let elevationBounds: ClosedRange<Int>?
    let difficulties: [String]
    @Binding var filter: HikeFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let bounds = walkingBounds {
                    RangeFilterSection(title: "Čas hoje", bounds: bounds,
                                       format: { HikeListModel.driveTimeText(seconds: $0 * 60) },
                                       selection: $filter.walkingRange)
                }
                if let bounds = elevationBounds {
                    RangeFilterSection(title: "Višinska razlika po poti", bounds: bounds,
                                       format: { "\($0) m" },
                                       selection: $filter.elevationRange)
                }
                if !difficulties.isEmpty {
                    Section("Zahtevnost") {
                        ForEach(difficulties, id: \.self) { value in
                            Toggle(value, isOn: binding(for: value))
                        }
                    }
                }
                Section {
                    Button("Počisti filtre", role: .destructive) { filter = HikeFilter() }
                        .disabled(!filter.isActive)
                }
            }
            .navigationTitle("Filtri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Končano") { dismiss() } }
            }
        }
    }

    /// nil difficulty set means "all allowed"; the set materializes on first toggle-off
    /// and collapses back to nil when every value is on again.
    private func binding(for value: String) -> Binding<Bool> {
        Binding(
            get: { filter.difficulties?.contains(value) ?? true },
            set: { isOn in
                var selected = filter.difficulties ?? Set(difficulties)
                if isOn { selected.insert(value) } else { selected.remove(value) }
                filter.difficulties = selected == Set(difficulties) ? nil : selected
            })
    }
}

/// Min/max pair of sliders over the values present in saved hikes.
/// nil selection = filter inactive (sliders sit at the bounds).
struct RangeFilterSection: View {
    let title: String
    let bounds: ClosedRange<Int>
    let format: (Int) -> String
    @Binding var selection: ClosedRange<Int>?

    var body: some View {
        Section(title) {
            let current = selection ?? bounds
            LabeledContent("Od", value: format(current.lowerBound))
            Slider(value: Binding(
                get: { Double(current.lowerBound) },
                set: { newValue in
                    let lower = min(Int(newValue), current.upperBound)
                    selection = lower...current.upperBound
                }), in: Double(bounds.lowerBound)...Double(bounds.upperBound), step: 1)
            LabeledContent("Do", value: format(current.upperBound))
            Slider(value: Binding(
                get: { Double(current.upperBound) },
                set: { newValue in
                    let upper = max(Int(newValue), current.lowerBound)
                    selection = current.lowerBound...upper
                }), in: Double(bounds.lowerBound)...Double(bounds.upperBound), step: 1)
        }
    }
}
