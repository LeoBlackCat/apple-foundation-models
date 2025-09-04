//
//  ClassicSpeechRecognizer.swift
//  FoundationModelsApp
//
//  Created by Leo on 6/16/25.
//

import Foundation
import Speech
import SwiftUI
import AVFoundation

enum SupportedLocale: String, CaseIterable {
    case arabicSA = "ar-SA"
    
    var displayName: String {
        return "Arabic (Saudi Arabia)"
    }
    
    var locale: Locale {
        return Locale(components: .init(languageCode: .arabic, script: nil, languageRegion: .saudiArabia))
    }
}

@Observable
final class ClassicSpeechRecognizer: NSObject, Sendable {
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    
    var transcriptText: String = ""
    var isRecording: Bool = false
    var selectedLocale: SupportedLocale = .arabicSA {
        didSet {
            setupRecognizer()
        }
    }
    
    override init() {
        super.init()
        setupRecognizer()
    }
    
    private func setupRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: selectedLocale.locale)
        speechRecognizer?.delegate = self
        
        print("Classic speech recognizer set up for locale: \(selectedLocale.locale.identifier(.bcp47))")
        print("Is available: \(speechRecognizer?.isAvailable ?? false)")
    }
    
    func requestPermissions() async -> Bool {
        // Request speech recognition permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        guard speechStatus == .authorized else {
            print("Speech recognition not authorized: \(speechStatus)")
            return false
        }
        
        // Request microphone permission
        let microphoneAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphoneAuthorized else {
            print("Microphone access denied")
            return false
        }
        
        return true
    }
    
    func startRecording() async throws {
        print("Starting classic speech recognition...")
        
        // Cancel any previous task
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        // Clear previous transcript
        transcriptText = ""
        
        // Check permissions
        guard await requestPermissions() else {
            throw TranscriptionError.permissionDenied
        }
        
        // Set up audio session (iOS only)
#if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
#endif
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw TranscriptionError.failedToSetupRecognitionStream
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Create recognition task
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw TranscriptionError.localeNotSupported
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcribedText = result.bestTranscription.formattedString
                print("Classic transcription: \(transcribedText) (isFinal: \(result.isFinal))")
                
                Task { @MainActor in
                    self.transcriptText = transcribedText
                }
            }
            
            if let error = error {
                print("Classic speech recognition error: \(error)")
                Task { @MainActor in
                    self.isRecording = false
                }
            }
        }
        
        // Set up audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        isRecording = true
        print("Classic speech recognition started successfully")
    }
    
    func stopRecording() {
        print("Stopping classic speech recognition...")
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isRecording = false
        print("Classic speech recognition stopped")
    }
    
    func changeLocale(to newLocale: SupportedLocale) async {
        if isRecording {
            stopRecording()
        }
        selectedLocale = newLocale
    }
}

extension ClassicSpeechRecognizer: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        print("Classic speech recognizer availability changed: \(available)")
    }
}