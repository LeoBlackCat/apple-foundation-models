//
//  VoiceChatView.swift
//  FoundationModelsApp
//
//  Created by Leo on 11/06/2025.
//

import SwiftUI
import AVFoundation

struct VoiceChatView: View {
    @State private var voiceChatManager = VoiceChatManager()
    @State private var isVoiceChatActive = false
    @State private var currentTranscript = ""
    @State private var currentResponse = ""
    @State private var statusMessage = "Ready to start voice chat"
    @State private var conversationHistory: [ChatMessage] = []
    @State private var isListeningForInput = true
    @State private var isProcessing = false
    
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
                // Header with controls
                VStack(spacing: 12) {
                    HStack {
                        HStack(spacing: 8) {
                            // Status icon
                            Image(systemName: statusIconName)
                                .foregroundColor(statusIconColor)
                                .font(.title2)
                            
                            Text("Voice Chat")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                        }
                        
                        Spacer()
                        
                        // Clear conversation button
                        if !conversationHistory.isEmpty {
                            Button(action: {
                                conversationHistory.removeAll()
                                voiceChatManager.clearConversationHistory()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                    Text("Clear")
                                }
                                .foregroundColor(.red)
                                .font(.subheadline)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                            }
                        }
                        
                        // Start/Stop button
                        Button(action: {
                            Task {
                                await toggleVoiceChat()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isVoiceChatActive ? "stop.circle.fill" : "mic.circle.fill")
                                Text(isVoiceChatActive ? "Stop" : "Start")
                            }
                            .foregroundColor(isVoiceChatActive ? .red : .blue)
                            .font(.subheadline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                        }
                        .disabled(!isTTSServiceConfigured)
                    }
                }
                .padding(.top)
                
                // Conversation history
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(conversationHistory) { message in
                                ChatMessageView(message: message)
                                    .id(message.id)
                            }
                            
                            // Show current transcript as a user message if active
                            if isVoiceChatActive && !currentTranscript.isEmpty {
                                ChatMessageView(message: ChatMessage(
                                    id: UUID(),
                                    text: currentTranscript,
                                    isUser: true,
                                    timestamp: Date()
                                ))
                                .id("currentTranscript")
                            }
                            
                            // Show current response as an assistant message if active
                            if !currentResponse.isEmpty {
                                ChatMessageView(message: ChatMessage(
                                    id: UUID(),
                                    text: currentResponse,
                                    isUser: false,
                                    timestamp: Date()
                                ))
                                .id("currentResponse")
                            }
                            
                            // Show listening indicator when active but no transcript yet
                            if isVoiceChatActive && currentTranscript.isEmpty && isListeningForInput {
                                ListeningIndicatorView()
                                    .id("listeningIndicator")
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: conversationHistory.count) { _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: currentTranscript) { _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: currentResponse) { _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: isListeningForInput) { _ in
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            setupVoiceChatManager()
        }
    }
    
    private var isTTSServiceConfigured: Bool {
        switch ElevenLabsSettings.shared.selectedTTSService {
        case .elevenLabs:
            return ElevenLabsSettings.shared.isConfigured
        case .avSpeechSynthesizer, .vercel:
            return true // These don't require additional configuration
        }
    }
    
    private var statusIconName: String {
        if !isVoiceChatActive {
            return "mic.slash"
        } else if isProcessing {
            return "hourglass"
        } else if isListeningForInput {
            return "mic.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }
    
    private var statusIconColor: Color {
        if !isVoiceChatActive {
            return .gray
        } else if isProcessing {
            return .orange
        } else if isListeningForInput {
            return .green
        } else {
            return .blue
        }
    }
    
    private func setupVoiceChatManager() {
        voiceChatManager.onTranscriptUpdate = { transcript in
            DispatchQueue.main.async {
                self.currentTranscript = transcript
            }
        }
        
        voiceChatManager.onResponseUpdate = { response in
            DispatchQueue.main.async {
                self.currentResponse = response
                self.isListeningForInput = false
                self.isProcessing = false
            }
        }
        
        voiceChatManager.onStatusUpdate = { status in
            DispatchQueue.main.async {
                self.statusMessage = status
                // Set processing state based on status
                if status.contains("Processing") {
                    self.isProcessing = true
                } else {
                    self.isProcessing = false
                }
            }
        }
        
        voiceChatManager.onMessageFinalized = { text, isUser in
            DispatchQueue.main.async {
                // Add the finalized message to conversation history
                self.conversationHistory.append(ChatMessage(
                    id: UUID(),
                    text: text,
                    isUser: isUser,
                    timestamp: Date()
                ))
                
                // Clear current messages if they match the finalized ones
                if isUser {
                    self.currentTranscript = ""
                    self.isListeningForInput = false
                } else {
                    self.currentResponse = ""
                }
            }
        }
        
        voiceChatManager.onListeningStateChanged = {
            DispatchQueue.main.async {
                self.isListeningForInput = true
            }
        }
    }
    
    private func toggleVoiceChat() async {
        if isVoiceChatActive {
            // Stop voice chat
            do {
                try await voiceChatManager.stopVoiceChat()
                DispatchQueue.main.async {
                    self.isVoiceChatActive = false
                    // Clear any remaining current messages
                    self.currentTranscript = ""
                    self.currentResponse = ""
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Error stopping voice chat: \(error.localizedDescription)"
                }
            }
        } else {
            // Start voice chat
            do {
                try await voiceChatManager.startVoiceChat()
                DispatchQueue.main.async {
                    self.isVoiceChatActive = true
                    // Clear any previous current messages when starting
                    self.currentTranscript = ""
                    self.currentResponse = ""
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Error starting voice chat: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) {
            if !currentResponse.isEmpty {
                proxy.scrollTo("currentResponse", anchor: .bottom)
            } else if !currentTranscript.isEmpty {
                proxy.scrollTo("currentTranscript", anchor: .bottom)
            } else if isListeningForInput && isVoiceChatActive {
                proxy.scrollTo("listeningIndicator", anchor: .bottom)
            } else if !conversationHistory.isEmpty {
                proxy.scrollTo(conversationHistory.last?.id, anchor: .bottom)
            }
        }
    }
}

struct ListeningIndicatorView: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Listening...")
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Image(systemName: "mic.fill")
                        .font(.body)
                        .foregroundColor(.blue)
                        .scaleEffect(isAnimating ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
                }
                .padding()
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.primary)
                .cornerRadius(16)
                .frame(maxWidth: 280, alignment: .trailing)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct ChatMessage: Identifiable {
    let id: UUID
    let text: String
    let isUser: Bool
    let timestamp: Date
}

struct ChatMessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.text)
                        .padding()
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(16)
                        .frame(maxWidth: 280, alignment: .trailing)
                    
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.text)
                        .padding()
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(16)
                        .frame(maxWidth: 280, alignment: .leading)
                    
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }
}

struct VoiceChatSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Voice Chat Settings")
                    .font(.title2)
                    .fontWeight(.medium)
                
                VStack(spacing: 16) {
                    Text("ElevenLabs Configuration")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Key")
                            .font(.subheadline)
                        SecureField("Enter API Key", text: .init(
                            get: { ElevenLabsSettings.shared.apiKey },
                            set: { ElevenLabsSettings.shared.apiKey = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Voice ID")
                            .font(.subheadline)
                        TextField("Enter Voice ID", text: .init(
                            get: { ElevenLabsSettings.shared.voiceID },
                            set: { ElevenLabsSettings.shared.voiceID = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TTS Service")
                            .font(.subheadline)
                        Picker("TTS Service", selection: .init(
                            get: { ElevenLabsSettings.shared.selectedTTSService },
                            set: { ElevenLabsSettings.shared.selectedTTSService = $0 }
                        )) {
                            ForEach(TTSService.allCases, id: \.self) { service in
                                Text(service.displayName).tag(service)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.top, 8)
                    
                    if ElevenLabsSettings.shared.isConfigured {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("ElevenLabs is configured")
                                .foregroundColor(.green)
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                            Text("Please configure ElevenLabs to use voice chat")
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .padding()
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    VoiceChatView()
} 