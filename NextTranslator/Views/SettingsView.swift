import SwiftUI

/// Placeholder settings pane; bound to SettingsStore in the next phase.
struct SettingsView: View {
    var body: some View {
        Form {
            Text("Settings arrive in the next milestone.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 320)
    }
}
