import SwiftUI
import LidlezzCore

/// Paste-a-key window, opened from the panel while on trial or after it ends.
struct LicenseView: View {
    @EnvironmentObject var model: Model
    @State private var key = ""
    @State private var rejected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enter your license").font(.system(size: 15, weight: .semibold))
                    Text(model.licenseLine).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            TextField("LZ-…", text: $key).textFieldStyle(.roundedBorder).font(Theme.mono)
            if rejected { Text("That key is not valid.").font(.system(size: 12)).foregroundStyle(Theme.red) }
            HStack {
                Link("Buy a license", destination: Site.buy).font(.system(size: 12))
                Spacer()
                Button("Activate") { rejected = !model.activate(key) }
                    .buttonStyle(.borderedProminent).disabled(key.isEmpty)
            }
        }
        .padding(20)
    }
}
