//
//  ContentView.swift
//  FoundationModelsApp
//
//  Created by Leo on 11/06/2025.
//

import SwiftUI
import FoundationModels
import os

struct ContentView: View {
    @State private var response: String = ""
    @State private var isStreaming: Bool = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer? = nil
    @State private var userPrompt: String = "I'm in Dushanbe and want to go to Bishkek, but I don't want to cross into Uzbekistan. What are my options?"
    @State private var showCopiedAlert: Bool = false
    private let logger = Logger(subsystem: "com.yourapp.FoundationModelsApp", category: "ContentView")
    private var session: LanguageModelSession { LanguageModelSession(instructions: "You are a helpful travel assistant who provides accurate, realistic, and well-structured travel advice. Avoid making up transport companies or border crossings that don't exist. Always take into account regional geography and political realities when suggesting routes. Keep your response concise but informative.") }

    var body: some View {
        VStack(spacing: 0) {
            VStack {
                Text("FoundationModels Example")
                    .font(.title2)
                    .fontWeight(.medium)
                
                TextField("Enter your question", text: $userPrompt)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .disabled(isStreaming)
                
                if isStreaming {
                    ProgressView()
                }
                if isStreaming || elapsedTime > 0 {
                    Text(String(format: "Time elapsed: %.1fs", elapsedTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    if isStreaming {
                        Button("Stop") {
                            // To implement cancellation, you will need the API for it.
                            // For now, it does nothing.
                        }
                        .disabled(true)
                    } else {
                        Button("Start") {
                            Task {
                                await fetchResponse()
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .padding()
            .background(Color(.systemBackground))
            
            if !response.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(response)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
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
                Button(action: {
                    UIPasteboard.general.string = response
                    showCopiedAlert = true
                }) {
                    Label("Copy All", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding()
                .background(Color(.systemBackground))
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .alert("Copied to Clipboard", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        }
    }

    private func fetchResponse() async {
        isStreaming = true
        response = ""
        elapsedTime = 0
        let startDate = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
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
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    ContentView()
}
