//
//  ElevenLabsShared.swift
//  FoundationModelsApp
//
//  Created by Leo on 11/06/2025.
//

import Foundation
import SwiftUI

enum TTSService: String, CaseIterable {
    case elevenLabs = "ElevenLabs"
    case avSpeechSynthesizer = "AVSpeechSynthesizer"
    case vercel = "Vercel TTS"
    
    var displayName: String {
        return self.rawValue
    }
}

enum ElevenLabsError: Error {
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case audioGenerationFailed
    case missingAPIKey
    case missingVoiceID
    
    var description: String {
        switch self {
        case .invalidResponse:
            return "Invalid response from ElevenLabs API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .audioGenerationFailed:
            return "Failed to generate audio"
        case .missingAPIKey:
            return "ElevenLabs API key is not configured"
        case .missingVoiceID:
            return "ElevenLabs Voice ID is not configured"
        }
    }
}

enum VercelTTSError: Error {
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case audioGenerationFailed
    
    var description: String {
        switch self {
        case .invalidResponse:
            return "Invalid response from Vercel TTS API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .audioGenerationFailed:
            return "Failed to generate audio"
        }
    }
}

@Observable
final class ElevenLabsSettings {
    static let shared = ElevenLabsSettings()
    
    private let defaults = UserDefaults.standard
    private let apiKeyKey = "elevenLabsAPIKey"
    private let voiceIDKey = "elevenLabsVoiceID"
    private let useAVSpeechSynthKey = "useAVSpeechSynthesizer"
    private let ttsServiceKey = "selectedTTSService"
    
    var apiKey: String {
        get { defaults.string(forKey: apiKeyKey) ?? "" }
        set { defaults.set(newValue, forKey: apiKeyKey) }
    }
    
    var voiceID: String {
        get { defaults.string(forKey: voiceIDKey) ?? "" }
        set { defaults.set(newValue, forKey: voiceIDKey) }
    }
    
    var isConfigured: Bool {
        !apiKey.isEmpty && !voiceID.isEmpty
    }

    var useAVSpeechSynthesizer: Bool {
        get { defaults.bool(forKey: useAVSpeechSynthKey) }
        set { defaults.set(newValue, forKey: useAVSpeechSynthKey) }
    }
    
    var selectedTTSService: TTSService {
        get { 
            if let rawValue = defaults.string(forKey: ttsServiceKey),
               let service = TTSService(rawValue: rawValue) {
                return service
            }
            return .avSpeechSynthesizer // Default to AVSpeechSynthesizer
        }
        set { defaults.set(newValue.rawValue, forKey: ttsServiceKey) }
    }
} 