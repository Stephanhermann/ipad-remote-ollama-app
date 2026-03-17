# ipad-remote-ollama-app

![Platform](https://img.shields.io/badge/platform-iPadOS%2017+-0f172a)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-f97316)
![License](https://img.shields.io/badge/license-MIT-2563eb)

Eine iPad-App in SwiftUI, um auf eine remote installierte Ollama-Umgebung zuzugreifen.

Repository:
`Stephanhermann/ipad-remote-ollama-app`

## Uebersicht

Die App ist als iPad-Client fuer selbst gehostete oder im Netzwerk erreichbare Ollama-Server gedacht. Der Fokus liegt auf einem praktischen Tablet-Workflow mit Serverprofilen, Streaming, Spracheingabe und lokaler Speicherung.

## Funktionen

- Server-URL fuer einen entfernten Ollama-Host konfigurieren
- Authentifizierung ueber Bearer-Token oder Benutzername/Passwort
- Modelle ueber `/api/tags` laden
- Chat ueber `/api/chat` mit optionalem Live-Streaming
- Modellwahl und System-Prompt direkt in der App
- Mehrere gespeicherte Chat-Sitzungen lokal im App-Storage
- Spracheingabe ueber Mikrofon und iPad-optimiertes Split-Layout mit separatem Einstellungsfenster
- Push-to-talk, Chat-Export/Import als JSON und Markdown-Darstellung fuer Antworten
- Mehrere Serverprofile sowie Bild-Upload fuer multimodale Ollama-Modelle
- Chat-Suche, grobe Token-/Zeichenzahler und dunkleres Chat-Layout fuer bessere Lesbarkeit
- Onboarding beim ersten Start, sichtbare Status-/Fehlerbanner und Verbindungs-Test pro Serverprofil
- Auto-ausblendende Banner, Serverprofil-Duplikate und ein erstes App-Icon/Launch-Motiv

## Projekt oeffnen

1. `~/Desktop/OllamaRemotePad/OllamaRemotePad.xcodeproj` in Xcode oeffnen
2. Team und Bundle Identifier setzen
3. iPad-Simulator oder echtes iPad waehlen
4. Server-URL auf deinen Ollama-Host setzen, zum Beispiel `http://192.168.1.10:11434`

## Release

- Aktuelle Release-Linie: `v0.1.0`
- Aenderungen: `CHANGELOG.md`

## Hinweise

- Fuer lokale oder unverschluesselte HTTP-Verbindungen ist `NSAllowsArbitraryLoads` aktiviert.
- Wenn dein Ollama-Server abgesichert werden soll, setze besser einen HTTPS-Reverse-Proxy davor.
- Im aktuellen Umfeld konnte ich das Projekt nicht mit `xcodebuild` bauen, weil nur die Command Line Tools aktiv sind und kein volles Xcode bereitsteht.

## Lizenz

MIT, siehe `LICENSE`.

## Weitere Texte

- Datenschutz: `PRIVACY.md`
- App-Store- und Screenshot-Texte: `APP_STORE_TEXTS.md`
- Changelog: `CHANGELOG.md`
