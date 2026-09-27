import JustThisCore
import ServiceManagement
import SwiftUI

/// UserDefaults keys. The shell reads them; the settings window writes them via @AppStorage.
enum Setting {
    static let focus = "focus"
    static let homeX = "homeX"
    static let homeY = "homeY"
    static let dodgeEnabled = "dodgeEnabled"
    static let dodgeDistance = "dodgeDistance"
    static let showReachHint = "showReachHint"
    static let fontSize = "fontSize"
    static let opacity = "opacity"
    static let theme = "theme"
    static let breathe = "breathe"

    static var defaults: [String: Any] { [
        dodgeEnabled: true,
        dodgeDistance: 24.0,
        showReachHint: true,
        fontSize: 13.0,
        opacity: 1.0,
        theme: "ember",
        breathe: true,
    ] }
}

struct SettingsView: View {
    let resetPosition: () -> Void

    @AppStorage(Setting.dodgeEnabled) private var dodgeEnabled = true
    @AppStorage(Setting.dodgeDistance) private var dodgeDistance = 24.0
    @AppStorage(Setting.showReachHint) private var showReachHint = true
    @AppStorage(Setting.fontSize) private var fontSize = 13.0
    @AppStorage(Setting.opacity) private var opacity = 1.0
    @AppStorage(Setting.theme) private var theme = "ember"
    @AppStorage(Setting.breathe) private var breathe = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Getting out of the way") {
                Toggle("Slide away when the cursor comes near", isOn: $dodgeEnabled)
                LabeledContent("Distance") {
                    HStack {
                        Slider(value: $dodgeDistance, in: 4...120)
                        Text("\(Int(dodgeDistance)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                .disabled(!dodgeEnabled)
                Toggle("Show “Hold ⌥ Option” hint when I keep reaching", isOn: $showReachHint)
                    .disabled(!dodgeEnabled)
            }

            Section("Look") {
                LabeledContent("Theme") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                        ForEach(Themes.all) { t in
                            ThemeSwatch(theme: t, selected: t.id == theme).onTapGesture { theme = t.id }
                        }
                    }
                    .frame(width: 290)
                }
                Toggle("Breathe (a slow, calm pulse)", isOn: $breathe)
                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $fontSize, in: 10...24, step: 1)
                        Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                LabeledContent("Opacity") {
                    HStack {
                        Slider(value: $opacity, in: 0.3...1)
                        Text("\(Int(opacity * 100))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
            }

            Section {
                LabeledContent("Position") {
                    Button("Reset to top centre", action: resetPosition)
                }
                Text("Hold ⌥ Option and drag the pill to rest it anywhere, on any display.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError { Text(loginError).font(.callout).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// A miniature pill in the theme's colours.
private struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(theme.accent)).frame(width: 7, height: 7)
                .shadow(color: Color(theme.accent), radius: 3)
            Text(theme.name).font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(theme.text))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        .background(Capsule().fill(Color(theme.background)))
        .overlay(Capsule().strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
        .contentShape(Capsule())
        .accessibilityLabel("\(theme.name) theme")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

extension Color {
    init(_ c: RGB) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b) }
}
