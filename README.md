# Foundation Models App

A SwiftUI app that demonstrates the use of Foundation Models for text generation and voice interaction.

## Features

### Text Chat
- Interactive chat interface with Foundation Models
- Real-time streaming responses
- Copy responses to clipboard

### Voice Chat (New!)
- **Continuous voice conversation** - Speak naturally and get spoken responses
- **Silence detection** - Automatically processes your message when you stop talking
- **ElevenLabs integration** - High-quality AI voice synthesis for responses
- **Conversation history** - View your chat history with timestamps
- **No manual input** - Pure voice interaction, just like talking to a person

## Setup

### ElevenLabs Configuration (Required for Voice Chat)

1. Get an API key from [ElevenLabs](https://elevenlabs.io/)
2. Get a Voice ID from your ElevenLabs dashboard
3. In the app, go to Settings tab and enter your:
   - API Key
   - Voice ID

### Voice Chat Usage

1. Go to the "Voice Chat" tab
2. Tap "Start Voice Chat"
3. Speak your message naturally
4. When you stop talking (2 seconds of silence), the app will:
   - Process your speech with the language model
   - Generate a response
   - Speak the response back to you using ElevenLabs
   - Start listening for your next message
5. Tap "Stop Voice Chat" when done

## Technical Details

- Built with SwiftUI and Foundation Models
- Uses Apple's Speech framework for real-time transcription
- Integrates with ElevenLabs API for high-quality voice synthesis
- Implements silence detection for natural conversation flow
- Supports conversation history and management

## Requirements

- iOS 17.0+
- Xcode 15.0+
- ElevenLabs API key and Voice ID
- Microphone permission
