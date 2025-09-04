# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a simplified SwiftUI macOS/iOS application called "FoundationModelsApp" that provides speech-to-text transcription using Apple's Speech framework. The app supports switching between English (US) and Arabic (Saudi Arabia) locales for speech recognition.

## Key Features

- **Real-time Speech Transcription**: Live speech-to-text conversion using Apple's SpeechTranscriber
- **Multi-language Support**: Switch between English (US) and Arabic (Saudi Arabia)
- **Live Transcription Display**: Shows both volatile (in-progress) and finalized transcription text
- **Simple Interface**: Clean, focused UI for speech transcription only

## Architecture

### Core Components

- **ContentView.swift**: Main UI with language selector, recording controls, and transcription display
- **SpokenWordTranscriber.swift**: Core speech recognition logic with locale switching support
- **Recorder.swift**: Audio input management and microphone permission handling
- **BufferConverter.swift**: Audio format conversion utilities
- **Helpers.swift**: Error definitions and transcription-related enums

### Key Classes

- `SpokenWordTranscriber`: @Observable class managing speech recognition with configurable locale support
- `SupportedLocale`: Enum defining available languages (English US, Arabic Saudi Arabia)
- `Recorder`: Audio recording and streaming to the transcriber
- `BufferConverter`: Handles audio format conversion between input and required formats

### Speech Processing Pipeline

1. **Locale Selection**: User selects between English US or Arabic (Saudi Arabia)
2. **Audio Input**: AVAudioEngine captures microphone input via Recorder
3. **Speech Recognition**: Apple's SpeechTranscriber converts audio to text in selected locale
4. **Live Display**: UI shows both volatile (in-progress) and finalized transcription results
5. **Model Management**: Automatic download and installation of required language models

## Development Commands

### Building and Running

```bash
# Open in Xcode
open FoundationModelsApp.xcodeproj

# Build from command line
xcodebuild -project FoundationModelsApp.xcodeproj -scheme FoundationModelsApp -configuration Debug

# Run tests
xcodebuild test -project FoundationModelsApp.xcodeproj -scheme FoundationModelsApp -destination 'platform=macOS'
```

### Key Frameworks

- **SwiftUI**: Modern declarative UI framework
- **Speech**: Apple's speech recognition and transcription framework
- **AVFoundation**: Audio recording and format handling
- **Foundation**: Core system frameworks

## Configuration Requirements

### Permissions

- **Microphone**: Required for speech transcription functionality (`NSMicrophoneUsageDescription` in Info.plist)
- **Speech Recognition**: Automatic permission request for speech services

### Supported Locales

The app currently supports:
- **English (US)**: `en-US` locale identifier
- **Arabic (Saudi Arabia)**: `ar-SA` locale identifier

Additional locales can be added by extending the `SupportedLocale` enum.

## File Structure

```
FoundationModelsApp/
├── ContentView.swift          # Main transcription UI
├── FoundationModelsAppApp.swift # App entry point
├── Helpers/
│   ├── SpokenWordTranscriber.swift # Speech recognition logic
│   ├── Recorder.swift         # Audio input management
│   ├── BufferConverter.swift  # Audio format conversion
│   └── Helpers.swift          # Error definitions
└── Assets.xcassets/          # App assets
```

## Testing

The project includes unit tests (`FoundationModelsAppTests`) and UI tests (`FoundationModelsAppUITests`). Run tests using:

```bash
# Run all tests
xcodebuild test -project FoundationModelsApp.xcodeproj -scheme FoundationModelsApp

# Run specific test target
xcodebuild test -project FoundationModelsApp.xcodeproj -scheme FoundationModelsApp -only-testing:FoundationModelsAppTests
```

## Key Implementation Details

### Locale Switching

1. User selects locale from segmented picker
2. `SpokenWordTranscriber.changeLocale(to:)` stops current transcription
3. New transcriber setup with selected locale
4. Automatic model download if not already installed

### Audio Pipeline

1. `Recorder` requests microphone permission
2. AVAudioEngine captures audio input
3. `BufferConverter` converts audio to required format
4. Audio streams to `SpeechTranscriber` via AsyncStream
5. Real-time transcription results displayed in UI

### Model Management

- Automatic checking for locale support via `SpeechTranscriber.supportedLocales`
- Model installation detection via `SpeechTranscriber.installedLocales`
- Download progress tracking with `AssetInventory.assetInstallationRequest`
- Proper model cleanup with `AssetInventory.deallocate`

### Error Handling

- `TranscriptionError` enum defines all possible transcription failures
- Graceful degradation when locale models are unavailable
- User feedback for permission denials and network issues

### Performance Considerations

- Efficient audio format conversion with `BufferConverter`
- Proper audio session management for recording
- Memory management with proper cleanup of audio resources
- Async/await pattern throughout for non-blocking operations

## Development Notes

- The app uses Apple's modern Speech framework with `SpeechTranscriber`
- UI state management uses `@Observable` macro for SwiftUI
- Audio processing uses `AsyncStream` for efficient real-time streaming
- Locale switching dynamically reconfigures the speech recognition pipeline
- The interface is designed for simplicity and focused functionality