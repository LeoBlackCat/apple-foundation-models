//
//  VoiceChatManager.swift
//  FoundationModelsApp
//
//  Created by Leo on 11/06/2025.
//

import Foundation
import FoundationModels
import Speech
import AVFoundation
import SwiftUI
import os

@Observable
final class VoiceChatManager: NSObject, Sendable, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<(), Error>?
    private var audioEngine: AVAudioEngine
    private var audioPlayer: AVAudioPlayer?
    private var silenceTimer: Timer?
    private var isListening = false
    private var isProcessing = false
    private var isSpeaking = false
    private var isListeningForInput = true
    
    // Audio session management
    private var audioSession: AVAudioSession?
    
    // ElevenLabs API configuration
    private let elevenLabsEndpoint = "https://api.elevenlabs.io/v1/text-to-speech/"
    
    // Silence detection settings
    private let silenceThreshold: TimeInterval = 2.0 // 2 seconds of silence
    private var lastSpeechTime: Date = Date()
    
    // Current conversation state
    private var currentTranscript: String = ""
    private var conversationHistory: [String] = []
    
    // Language model session
    private var session: LanguageModelSession?
    
    // The format of the audio
    var analyzerFormat: AVAudioFormat?
    var converter = BufferConverter()
    
    // Callbacks for UI updates
    var onTranscriptUpdate: ((String) -> Void)?
    var onResponseUpdate: ((String) -> Void)?
    var onStatusUpdate: ((String) -> Void)?
    var onMessageFinalized: ((String, Bool) -> Void)? // text, isUser
    var onListeningStateChanged: (() -> Void)?
    var onAudioFinished: (() -> Void)?
    
    private let logger = Logger(subsystem: "com.yourapp.FoundationModelsApp", category: "VoiceChatManager")
    
    static let locale = Locale(components: .init(languageCode: .english, script: nil, languageRegion: .unitedStates))
    
    override init() {
        self.audioEngine = AVAudioEngine()
        super.init()
        setupLanguageModel()
    }
    
    private func setupLanguageModel() {
        session = LanguageModelSession(instructions: """
        You are a helpful AI assistant. Keep your responses concise and conversational, 
        ideally 1-3 sentences, since your responses will be spoken out loud. 
        Be friendly and engaging in your conversation.
        """)
    }
    
    func startVoiceChat() async throws {
        guard !isListening else { return }
        
        isListening = true
        onStatusUpdate?("Starting voice chat...")
        
        // Setup audio session
        try await setupAudioSession()
        
        // Setup speech recognition
        try await setupSpeechRecognition()
        
        // Start listening
        try await startListening()
        
        onStatusUpdate?("Listening...")
    }
    
    func stopVoiceChat() async throws {
        isListening = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        try await stopListening()
        onStatusUpdate?("Voice chat stopped")
    }
    
    private func setupAudioSession() async throws {
#if os(iOS)
        audioSession = AVAudioSession.sharedInstance()
        try audioSession?.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession?.setActive(true, options: .notifyOthersOnDeactivation)
#endif
    }
    
    private func setupAudioSessionForPlayback() async throws {
#if os(iOS)
        try audioSession?.setCategory(.playback, mode: .spokenAudio, options: [.defaultToSpeaker])
        try audioSession?.setActive(true, options: .notifyOthersOnDeactivation)
#endif
    }
    
    private func setupAudioSessionForRecording() async throws {
#if os(iOS)
        try audioSession?.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession?.setActive(true, options: .notifyOthersOnDeactivation)
#endif
    }
    
    private func setupSpeechRecognition() async throws {
        transcriber = SpeechTranscriber(locale: VoiceChatManager.locale,
                                      transcriptionOptions: [],
                                      reportingOptions: [.volatileResults],
                                      attributeOptions: [.audioTimeRange])
        
        guard let transcriber else {
            throw TranscriptionError.failedToSetupRecognitionStream
        }
        
        analyzer = SpeechAnalyzer(modules: [transcriber])
        
        do {
            try await ensureModel(transcriber: transcriber, locale: VoiceChatManager.locale)
        } catch let error as TranscriptionError {
            logger.error("Failed to ensure model: \(error.localizedDescription)")
            throw error
        }
        
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        
        guard let inputSequence else { 
            throw TranscriptionError.failedToSetupRecognitionStream
        }
        
        recognizerTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = result.text
                    
                    if result.isFinal {
                        currentTranscript = String(text.characters)
                        lastSpeechTime = Date()
                        isListeningForInput = false
                        onListeningStateChanged?()
                        onTranscriptUpdate?(String(text.characters))
                        
                        // Reset silence timer
                        silenceTimer?.invalidate()
                        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { _ in
                            Task {
                                await self.processUserInput()
                            }
                        }
                    } else {
                        // Update volatile transcript
                        onTranscriptUpdate?(String(text.characters))
                    }
                }
            } catch {
                logger.error("Speech recognition failed: \(error.localizedDescription)")
            }
        }
        
        try await analyzer?.start(inputSequence: inputSequence)
    }
    
    private func startListening() async throws {
        try setupAudioEngine()
        
        audioEngine.inputNode.installTap(onBus: 0,
                                       bufferSize: 4096,
                                       format: audioEngine.inputNode.outputFormat(forBus: 0)) { [weak self] (buffer, time) in
            guard let self else { return }
            Task {
                try await self.streamAudioToTranscriber(buffer)
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
    }
    
    private func stopListening() async throws {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        inputBuilder?.finish()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
    }
    
    private func setupAudioEngine() throws {
        // Audio engine setup is handled in startListening
    }
    
    private func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer) async throws {
        guard let inputBuilder, let analyzerFormat else {
            throw TranscriptionError.invalidAudioDataType
        }
        
        let converted = try self.converter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)
        
        inputBuilder.yield(input)
    }
    
    private func processUserInput() async {
        guard !currentTranscript.isEmpty && !isProcessing else { return }
        
        isProcessing = true
        isListeningForInput = false
        onListeningStateChanged?()
        onStatusUpdate?("Processing...")
        
        // Store the transcript before clearing
        let userInput = currentTranscript
        currentTranscript = ""
        
        // Add to conversation history
        conversationHistory.append(userInput)
        
        // Notify UI that user message is finalized
        onMessageFinalized?(userInput, true)
        
        do {
            // Get response from language model
            guard let session = session else {
                throw NSError(domain: "VoiceChat", code: 1, userInfo: [NSLocalizedDescriptionKey: "Language model not initialized"])
            }
            
            var response = ""
            for try await segment in session.streamResponse(to: userInput) {
                response = segment
                onResponseUpdate?(response)
            }
            
            // Add response to conversation history
            conversationHistory.append(response)
            
            // Notify UI that assistant message is finalized
            onMessageFinalized?(response, false)
            
            // Generate and play speech
            await playResponse(response)
            
        } catch {
            logger.error("Failed to process user input: \(error.localizedDescription)")
            onStatusUpdate?("Error: \(error.localizedDescription)")
        }
        
        // Reset for next input
        isProcessing = false
        onStatusUpdate?("Listening...")
    }
    
    private func playResponse(_ text: String) async {
        guard !text.isEmpty else { return }
        
        isSpeaking = true
        isListeningForInput = false
        onStatusUpdate?("Speaking...")
        
        // Pause listening while speaking
        try? await pauseListening()
        
        switch ElevenLabsSettings.shared.selectedTTSService {
        case .avSpeechSynthesizer:
            // Use AVSpeechSynthesizer
            await MainActor.run {
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                let synthesizer = AVSpeechSynthesizer()
                synthesizer.delegate = self
                synthesizer.speak(utterance)
            }
            // Resume listening will be handled in delegate
            
        case .elevenLabs:
            do {
                let audioURL = try await generateElevenLabsSpeech(text: text)
                await MainActor.run {
                    // Switch to playback mode
                    Task {
                        try? await self.setupAudioSessionForPlayback()
                    }
                    playAudioFile(url: audioURL)
                }
            } catch let error as ElevenLabsError {
                logger.error("ElevenLabs error: \(error.description)")
                onStatusUpdate?("Speech generation failed: \(error.description)")
                // Resume listening even if speech generation failed
                try? await resumeListening()
            } catch {
                logger.error("Unexpected error: \(error.localizedDescription)")
                onStatusUpdate?("Speech generation failed: \(error.localizedDescription)")
                // Resume listening even if speech generation failed
                try? await resumeListening()
            }
            
        case .vercel:
            do {
                let audioURL = try await generateVercelSpeech(text: text)
                await MainActor.run {
                    // Switch to playback mode
                    Task {
                        try? await self.setupAudioSessionForPlayback()
                    }
                    playAudioFile(url: audioURL)
                }
            } catch let error as VercelTTSError {
                logger.error("Vercel TTS error: \(error.description)")
                onStatusUpdate?("Speech generation failed: \(error.description)")
                // Resume listening even if speech generation failed
                try? await resumeListening()
            } catch {
                logger.error("Unexpected error: \(error.localizedDescription)")
                onStatusUpdate?("Speech generation failed: \(error.localizedDescription)")
                // Resume listening even if speech generation failed
                try? await resumeListening()
            }
        }
        
        isSpeaking = false
    }
    
    private func pauseListening() async throws {
        audioEngine.pause()
        onStatusUpdate?("Speaking...")
    }
    
    private func resumeListening() async throws {
        // Switch back to recording mode
        try await setupAudioSessionForRecording()
        try audioEngine.start()
        onStatusUpdate?("Listening...")
    }
    
    private func generateElevenLabsSpeech(text: String) async throws -> URL {
        guard ElevenLabsSettings.shared.isConfigured else {
            throw ElevenLabsError.missingAPIKey
        }
        
        let url = URL(string: elevenLabsEndpoint + ElevenLabsSettings.shared.voiceID)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ElevenLabsSettings.shared.apiKey, forHTTPHeaderField: "xi-api-key")
        
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                logger.error("Error response data: \(errorJson)")
                if let detail = errorJson["detail"] as? String {
                    throw ElevenLabsError.apiError(detail)
                }
                if httpResponse.statusCode == 401 {
                    if let message = errorJson["message"] as? String {
                        throw ElevenLabsError.apiError("Authentication failed: \(message)")
                    }
                    throw ElevenLabsError.apiError("Authentication failed: Invalid API key")
                }
            }
            throw ElevenLabsError.httpError(httpResponse.statusCode)
        }
        
        // Save the audio data to a temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            throw ElevenLabsError.audioGenerationFailed
        }
    }
    
    private func playAudioFile(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            logger.error("Failed to play audio file: \(error.localizedDescription)")
        }
    }
    
    private func generateVercelSpeech(text: String) async throws -> URL {
        let url = URL(string: "https://edge-tts-stream-api.vercel.app/tts/stream")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "voice": "en-US-AvaMultilingualNeural",
            "text": text
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VercelTTSError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                logger.error("Error response data: \(errorJson)")
                if let detail = errorJson["detail"] as? String {
                    throw VercelTTSError.apiError(detail)
                }
            }
            throw VercelTTSError.httpError(httpResponse.statusCode)
        }
        
        // Save the audio data to a temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            throw VercelTTSError.audioGenerationFailed
        }
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        logger.debug("Started speaking")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        logger.debug("AVSpeechSynthesizer finished speaking")
        isListeningForInput = true
        onListeningStateChanged?()
        Task {
            if isListening && !isProcessing {
                try? await resumeListening()
            }
        }
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        logger.debug("Audio playback finished")
        isListeningForInput = true
        onListeningStateChanged?()
        
        // Resume listening after audio finishes playing
        Task {
            if isListening && !isProcessing {
                try? await resumeListening()
            }
        }
    }
    
    func clearConversationHistory() {
        conversationHistory.removeAll()
    }
}

// MARK: - Model Management Extensions

extension VoiceChatManager {
    public func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        guard await supported(locale: locale) else {
            throw TranscriptionError.localeNotSupported
        }
        
        if await installed(locale: locale) {
            return
        } else {
            try await downloadIfNeeded(for: transcriber)
        }
    }
    
    func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        logger.debug("Supported locales: \(supported.map { $0.identifier(.bcp47) })")
        return supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }
    
    func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        return installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }
    
    func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await downloader.downloadAndInstall()
        }
    }
    
    func deallocate() async {
        let allocated = await AssetInventory.allocatedLocales
        for locale in allocated {
            await AssetInventory.deallocate(locale: locale)
        }
    }
} 

