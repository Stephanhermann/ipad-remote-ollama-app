import SwiftUI

struct OnboardingView: View {
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    Text("OllamaRemotePad")
                        .font(.largeTitle.weight(.bold))
                    Text("Greife vom iPad aus auf deine remote installierte Ollama-Umgebung zu.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(title: "1. Serverprofil anlegen", text: "Trage URL und Authentifizierung deines Ollama-Servers ein.")
                    FeatureRow(title: "2. Verbindung testen", text: "Pruefe direkt in den Einstellungen, ob das Profil erreichbar ist.")
                    FeatureRow(title: "3. Modell laden und chatten", text: "Lade Modelle, starte Chats und sende bei Bedarf auch Bilder.")
                }

                Spacer()

                Button("Loslegen") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(32)
            .navigationTitle("Willkommen")
        }
    }
}

private struct FeatureRow: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}
