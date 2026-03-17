import AVFoundation
import Foundation
import Speech
import SwiftUI

@MainActor
final class SpeechRecognizer: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var targetText: Binding<String>?

    func startRecording(into text: Binding<String>) async {
        guard !isRecording else { return }
        errorMessage = nil
        targetText = text

        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            errorMessage = "Spracherkennung wurde nicht erlaubt."
            return
        }

        let microphoneGranted = await requestMicrophoneAuthorization()
        guard microphoneGranted else {
            errorMessage = "Mikrofonzugriff wurde nicht erlaubt."
            return
        }

        stopRecording()

        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Audio-Session konnte nicht gestartet werden."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Aufnahme konnte nicht gestartet werden."
            cleanup()
            return
        }

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.targetText?.wrappedValue = result.bestTranscription.formattedString
                if result.isFinal {
                    self.stopRecording()
                }
            }

            if error != nil {
                self.errorMessage = "Spracherkennung wurde beendet."
                self.stopRecording()
            }
        }

        isRecording = true
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        cleanup()
    }

    private func cleanup() {
        task?.cancel()
        task = nil
        request = nil
        targetText = nil
        isRecording = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Audio-Session kann beim Beenden stillschweigend fehlschlagen.
        }
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
