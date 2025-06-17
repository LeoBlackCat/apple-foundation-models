//
//  ContentView.swift
//  FoundationModelsApp
//
//  Created by Leo on 11/06/2025.
//

import SwiftUI
import FoundationModels
import os
import Speech
import AVFoundation

class SpeechSynthDelegate: NSObject, AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("Started speaking")
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("Finished speaking")
    }
}

struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .cornerRadius(16)
    }
}

struct GlassButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    let isDisabled: Bool
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.ultraThinMaterial)
            .foregroundColor(isDisabled ? .gray : .primary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .disabled(isDisabled)
    }
}

struct ContentView: View {
    @State private var synthesizer = AVSpeechSynthesizer()
    @Binding var story: Story
    @State var isRecording = false
    @State var isPlaying = false
    
    @State var recorder: Recorder? = nil
    @State var speechTranscriber: SpokenWordTranscriber? = nil
    
    @State var downloadProgress = 0.0
    
    @State var currentPlaybackTime = 0.0
    
    @State var timer: Timer?
       
    @State private var response: String = ""
    @State private var isStreaming: Bool = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var modelTimer: Timer? = nil
    @State private var transcriptionText: String = ""
    @State private var isTranscribing: Bool = false
    @State private var supportedLocales: [Locale] = []
    @State private var selectedLocale: Locale = .current
    @State private var userPrompt: String = "What's a common law?"
    @State private var showCopiedAlert: Bool = false
    @State private var selectedTab: Int = 3  // Set default tab to transcription
    @State private var speechSynthDelegate = SpeechSynthDelegate()
    
    private let logger = Logger(subsystem: "com.yourapp.FoundationModelsApp", category: "ContentView")
    private var session: LanguageModelSession { LanguageModelSession(instructions: """
        American Legal System – Key Concepts

        America was founded on the idea that government power comes from the people.
        Laws can be challenged and changed by citizens through voting and courts.
        The U.S. uses a common law system: both written laws and judicial decisions matter.
        It's also an adversarial system: two sides argue their case before a judge or jury.
        Lawyers play key roles in government, business, and regulation.

        Explain all these concepts to the user based on your knowledge and answer their questions clearly and simply.
        """) }
    //private var session: LanguageModelSession { LanguageModelSession(instructions: "You are a helpful grammar assistant") }

    init(story: Binding<Story>) {
        self._story = story
        // Removed initialization of recorder and speechTranscriber here
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            TabView(selection: $selectedTab) {
                // Chat Tab
                VStack(spacing: 16) {
                    VStack(spacing: 16) {
                        Text("Foundation Models")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        
                        TextEditor(text: $userPrompt)
                            .frame(height: 100)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .disabled(isStreaming)
                        
                        if isStreaming {
                            ProgressView()
                                .scaleEffect(1.2)
                        }
                        if isStreaming || elapsedTime > 0 {
                            Text(String(format: "Time elapsed: %.1fs", elapsedTime))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 12) {
                            if isStreaming {
                                GlassButton(
                                    title: "Stop",
                                    systemImage: "stop.circle.fill",
                                    action: { },
                                    isDisabled: true
                                )
                            } else {
                                GlassButton(
                                    title: "Start",
                                    systemImage: "play.circle.fill",
                                    action: {
                                        Task {
                                            await fetchResponse()
                                        }
                                    },
                                    isDisabled: false
                                )
                            }
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .padding()
                    
                    if !response.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView {
                                Text(.init(response))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(16)
                                    .padding(.horizontal)
                                    .textSelection(.enabled)
                                    .id("responseText")
                            }
                            .onChange(of: response) { _ in
                                DispatchQueue.main.async {
                                    withAnimation {
                                        proxy.scrollTo("responseText", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    } else {
                        Spacer()
                    }
                    
                    if !response.isEmpty {
                        GlassButton(
                            title: "Copy All",
                            systemImage: "doc.on.doc",
                            action: {
#if os(iOS)
                                UIPasteboard.general.string = response
#endif
                                showCopiedAlert = true
                            },
                            isDisabled: false
                        )
                        .padding(.horizontal)
                    }
                }
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .tag(0)
                
                // History Tab
                VStack {
                    Text("History")
                        .font(.title2)
                        .fontWeight(.medium)
                    Spacer()
                }
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(1)
                
                // Settings Tab
                VStack {
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    GlassButton(
                        title: "Test Speech",
                        systemImage: "speaker.wave.2",
                        action: {
                            if AVAudioSession.sharedInstance().category != .playback {
                                    do {
                                        try AVAudioSession.sharedInstance().setCategory(.playback)
                                    } catch {
                                        print(error)
                                    }
                                }
                            synthesizer.delegate = speechSynthDelegate
                            let voice = AVSpeechSynthesisVoice(language: "en-US")
                            let utterance = AVSpeechUtterance(string: "This is a test of the speech synthesis system.")
                            utterance.voice = voice
                            utterance.rate = 0.5
                            utterance.pitchMultiplier = 1.0
                            utterance.volume = 1.0
                            synthesizer.speak(utterance)
                        },
                        isDisabled: false
                    )
                    .padding()
                    
                    Spacer()
                }
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
                
                // Transcription Tab
                VStack(spacing: 16) {
                    Text("Text Transcription")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    if !supportedLocales.isEmpty {
                        Picker("Select Language", selection: $selectedLocale) {
                            ForEach(supportedLocales, id: \.identifier) { locale in
                                Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                                    .tag(locale)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    }
                    
                    Text((speechTranscriber?.finalizedTranscript ?? "") + (speechTranscriber?.volatileTranscript ?? ""))
                        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )

                    if !story.modelResponse.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView {
                                Text(.init(story.modelResponse))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(16)
                                    .padding(.horizontal)
                                    .textSelection(.enabled)
                                    .id("modelResponseText")
                            }
                            .onChange(of: story.modelResponse) { _ in
                                DispatchQueue.main.async {
                                    withAnimation {
                                        proxy.scrollTo("modelResponseText", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    
                    HStack(spacing: 12) {
                        GlassButton(
                            title: isRecording ? "Stop" : "Transcribe",
                            systemImage: isRecording ? "stop.circle.fill" : "waveform",
                            action: {
                                isRecording.toggle()
                            },
                            isDisabled: recorder == nil // Disable if recorder not initialized
                        )
                    }
                    
                    if !response.isEmpty {
                        ScrollView {
                            Text(.init(response))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(.ultraThinMaterial)
                                .cornerRadius(16)
                                .textSelection(.enabled)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
                .tabItem {
                    Label("Transcribe", systemImage: "waveform")
                }
                .tag(3)
            }
            .tint(.blue)
            .onAppear {
#if os(iOS)
                // Customize the tab bar appearance
                let appearance = UITabBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
                
                // Add blur effect
                let blurEffect = UIBlurEffect(style: .systemMaterial)
                appearance.backgroundEffect = blurEffect
                
                UITabBar.appearance().standardAppearance = appearance
                UITabBar.appearance().scrollEdgeAppearance = appearance
#endif
                session.prewarm()
                if speechTranscriber == nil {
                    let newTranscriber = SpokenWordTranscriber(story: $story)
                    speechTranscriber = newTranscriber
                    recorder = Recorder(transcriber: newTranscriber, story: $story)
                }
                //await loadSupportedLocales()
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .alert("Copied to Clipboard", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        }
        .task {
            session.prewarm()
            //await loadSupportedLocales()
        }
        .onChange(of: isRecording) { oldValue, newValue in
            guard newValue != oldValue else { return }
            if newValue == true {
                Task {
                    do {
                        try await recorder?.record()
                    } catch {
                        print("could not record: \(error)")
                    }
                }
            } else {
                Task {
                    try await recorder?.stopRecording()
                }
            }
        }
    }

    private func fetchResponse() async {
        isStreaming = true
        response = ""
        elapsedTime = 0
        let startDate = Date()
        modelTimer?.invalidate()
        modelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            elapsedTime = Date().timeIntervalSince(startDate)
        }
        do {
            for try await segment in session.streamResponse(to: userPrompt) {
                logger.debug("Received segment: \(segment)")
                response = segment
                logger.debug("Updated response length: \(segment.count)")
            }
        } catch {
            logger.error("Streaming error: \(error.localizedDescription)")
            response = "Failed to stream response: \(error.localizedDescription)"
        }
        isStreaming = false
        modelTimer?.invalidate()
        modelTimer = nil
    }
}



#Preview {
    ContentView(story: .constant(Story(title: "My Story", text: AttributedString("This is a sample story."))))
}
