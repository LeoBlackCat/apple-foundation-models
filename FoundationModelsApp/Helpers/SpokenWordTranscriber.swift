//
//  SpokenWordTranscriber.swift
//  FoundationModelsApp
//
//  Created by Leo on 6/16/25.
//


import Foundation
import FoundationModels
import Speech
import SwiftUI
import AVFoundation

@Observable
final class SpokenWordTranscriber: NSObject, Sendable, AVSpeechSynthesizerDelegate {
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<(), Error>?
    //private let synthesizer = AVSpeechSynthesizer()
    private var synth = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    
    // ElevenLabs API configuration
    private let elevenLabsEndpoint = "https://api.elevenlabs.io/v1/text-to-speech/"
    
    static let magenta = Color(red: 0.54, green: 0.02, blue: 0.6).opacity(0.8) // #e81cff
    
    // The format of the audio.
    var analyzerFormat: AVAudioFormat?
    
    var converter = BufferConverter()
    var downloadProgress: Progress?
    
    var story: Binding<Story>
    
    var volatileTranscript: AttributedString = ""
    var finalizedTranscript: AttributedString = ""
    
    static let locale = Locale(components: .init(languageCode: .english, script: nil, languageRegion: .unitedStates))
    
    init(story: Binding<Story>) {
        self.story = story
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("Started speaking")
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("Finished speaking")
    }
    
    func setUpTranscriber() async throws {
        transcriber = SpeechTranscriber(locale: SpokenWordTranscriber.locale,
                                        transcriptionOptions: [],
                                        reportingOptions: [.volatileResults],
                                        attributeOptions: [.audioTimeRange])

        guard let transcriber else {
            throw TranscriptionError.failedToSetupRecognitionStream
        }

        analyzer = SpeechAnalyzer(modules: [transcriber])
        
        do {
            try await ensureModel(transcriber: transcriber, locale:  SpokenWordTranscriber.locale)
        } catch let error as TranscriptionError {
            print(error)
            return
        }
        
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        
        guard let inputSequence else { return }
        
        recognizerTask = Task {
            do {
                for try await case let result in transcriber.results {
                    let text = result.text
                    print("transcribed text: \(text.characters) isFinal: \(result.isFinal)")
                    if result.isFinal {
                        finalizedTranscript += text
                        volatileTranscript = ""
                        updateStoryWithNewText(withFinal: text)
                    } else {
                        volatileTranscript = text
                        volatileTranscript.foregroundColor = .purple.opacity(0.4)
                    }
                }
            } catch {
                print("speech recognition failed")
            }
        }
        
        try await analyzer?.start(inputSequence: inputSequence)
    }
    
    func generateElevenLabsSpeech(text: String) async throws -> URL {
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
                print("Error response data: \(errorJson)")
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
    
    func playAudioFile(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Failed to play audio file: \(error)")
        }
    }
    
    func updateStoryWithNewText(withFinal str: AttributedString) {
        story.text.wrappedValue.append(str)
        
        // Trigger model response for the transcribed text
        Task {
            do {
                let session = LanguageModelSession(instructions: "Answer the question in a concise manner, 1-2 sentences, your output will be spoken out loud.")
 
                // Extract plain text from AttributedString
                let plainText = String(str.characters)
                
                for try await segment in session.streamResponse(to: plainText) {
                    story.modelResponse.wrappedValue = segment
                }
                
                // Generate and play speech using ElevenLabs
                do {
                    let audioURL = try await generateElevenLabsSpeech(text: story.modelResponse.wrappedValue)
                    await MainActor.run {
                        if AVAudioSession.sharedInstance().category != .playback {
                            do {
                                try AVAudioSession.sharedInstance().setCategory(.playback)
                            } catch {
                                print("Audio session error: \(error)")
                            }
                        }
                        playAudioFile(url: audioURL)
                    }
                } catch let error as ElevenLabsError {
                    print("ElevenLabs error: \(error.description)")
                    story.modelResponse.wrappedValue += "\n[Speech generation failed: \(error.description)]"
                } catch {
                    print("Unexpected error: \(error)")
                    story.modelResponse.wrappedValue += "\n[Speech generation failed: \(error.localizedDescription)]"
                }
            } catch {
                print("Failed to get model response: \(error)")
            }
        }
    }
    
    func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer) async throws {
        guard let inputBuilder, let analyzerFormat else {
            throw TranscriptionError.invalidAudioDataType
        }
        
        let converted = try self.converter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)
        
        inputBuilder.yield(input)
    }
    
    public func finishTranscribing() async throws {
        inputBuilder?.finish()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
    }
}

extension SpokenWordTranscriber {
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
        print("supported locales:")
        for locale in supported {
            print(locale.identifier(.bcp47))
        }
        print("checking if \(locale.identifier(.bcp47)) is supported")
        return supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }

    func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        return installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }

    func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            self.downloadProgress = downloader.progress
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

