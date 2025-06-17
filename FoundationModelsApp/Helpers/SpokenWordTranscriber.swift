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
                    print("transcribed text: \(text) isFinal: \(result.isFinal)")
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
                
                // After streaming is complete, play the response using text-to-speech
                await MainActor.run {
                    if AVAudioSession.sharedInstance().category != .playback {
                            do {
                                try AVAudioSession.sharedInstance().setCategory(.playback)
                            } catch {
                                print(error)
                            }
                        }
                    synth.delegate = self
                    let voice = AVSpeechSynthesisVoice(language: "en-US")
                    let utterance = AVSpeechUtterance(string: story.modelResponse.wrappedValue)
                    utterance.voice = voice
                    utterance.rate = 0.5 // Slightly slower rate for better clarity
                    utterance.pitchMultiplier = 1.0
                    utterance.volume = 1.0
                    synth.speak(utterance)
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

