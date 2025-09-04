//
//  ContentView.swift
//  FoundationModelsApp
//
//  Created by Leo on 11/06/2025.
//

import SwiftUI
import Speech
import AVFoundation

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
    @State private var isRecording = false
    @State private var speechRecognizer: ClassicSpeechRecognizer? = nil
    @State private var showCopiedAlert: Bool = false
    @State private var useArabizi: Bool = false
    
    init() {
        // Simple initialization
    }
    
    // Helper function to process transcription text based on settings
    private func processTranscriptionText(_ text: String) -> String {
        if useArabizi {
            return ArabiziTransliterator.transliterate(text)
        }
        return text
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
            
            VStack(spacing: 20) {
                // Header
                Text("Arabic Speech Transcriber")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                
                // Arabizi Output Toggle
                VStack(spacing: 12) {
                    Text("Output Format")
                        .font(.headline)
                    
                    HStack {
                        Text("Output Format:")
                            .font(.subheadline)
                        Spacer()
                        Toggle(isOn: $useArabizi) {
                            Text(useArabizi ? "Arabizi (mar7aba)" : "Arabic (مرحبا)")
                                .font(.subheadline)
                        }
                        .toggleStyle(.switch)
                        .onChange(of: useArabizi) { oldValue, newValue in
                            print("Arabizi output toggled: \(newValue)")
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                
                // Recording Controls
                VStack(spacing: 16) {
                    Text(isRecording ? "Recording..." : "Ready to Record")
                        .font(.title2)
                        .foregroundColor(isRecording ? .red : .primary)
                    
                    GlassButton(
                        title: isRecording ? "Stop Recording" : "Start Recording",
                        systemImage: isRecording ? "stop.circle.fill" : "mic.circle.fill",
                        action: {
                            isRecording.toggle()
                        },
                        isDisabled: false
                    )
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                
                // Transcription Display
                VStack(alignment: .leading, spacing: 12) {
                    Text("Transcription")
                        .font(.headline)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if let recognizer = speechRecognizer, !recognizer.transcriptText.isEmpty {
                                Text(processTranscriptionText(recognizer.transcriptText))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            } else {
                                Text("Transcribed text will appear here...")
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        }
                        .padding()
                    }
                    .frame(minHeight: 200)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Copy button
                    if let recognizer = speechRecognizer, !recognizer.transcriptText.isEmpty {
                        let processedText = processTranscriptionText(recognizer.transcriptText)
                        GlassButton(
                            title: "Copy Transcription",
                            systemImage: "doc.on.doc",
                            action: {
#if os(iOS)
                                UIPasteboard.general.string = processedText
#else
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(processedText, forType: .string)
#endif
                                showCopiedAlert = true
                            },
                            isDisabled: false
                        )
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                
                Spacer()
            }
            .padding()
        }
        .alert("Copied to Clipboard", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        }
        .onAppear {
            if speechRecognizer == nil {
                speechRecognizer = ClassicSpeechRecognizer()
            }
        }
        .onChange(of: isRecording) { oldValue, newValue in
            guard newValue != oldValue else { return }
            print("isRecording changed from \(oldValue) to \(newValue)")
            if newValue == true {
                Task {
                    do {
                        print("starting recording...")
                        try await speechRecognizer?.startRecording()
                        print("recording started")
                    } catch {
                        print("could not record: \(error)")
                        // Reset the UI state if recording fails
                        await MainActor.run {
                            isRecording = false
                        }
                    }
                }
            } else {
                speechRecognizer?.stopRecording()
                print("recording stopped")
            }
        }
    }
}

#Preview {
    ContentView()
}