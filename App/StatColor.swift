import SwiftUI

extension Color {
    /// Resolves per light/dark so each variant can be tuned for ≥4.5:1 contrast
    /// against the system grouped list background.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    // Fixed field-identity colors (spec): blue / orange / purple / teal.
    static let statWalking = Color(light: Color(red: 0.00, green: 0.27, blue: 0.68),
                                   dark: Color(red: 0.45, green: 0.66, blue: 1.00))
    static let statDifficulty = Color(light: Color(red: 0.58, green: 0.24, blue: 0.00),
                                      dark: Color(red: 1.00, green: 0.63, blue: 0.30))
    static let statElevation = Color(light: Color(red: 0.42, green: 0.13, blue: 0.66),
                                     dark: Color(red: 0.79, green: 0.57, blue: 1.00))
    static let statDrive = Color(light: Color(red: 0.00, green: 0.35, blue: 0.34),
                                 dark: Color(red: 0.31, green: 0.80, blue: 0.77))
}
