# 🧠 Astra Assistant

**Private, local-first AI assistant** for macOS with iPhone companion app.

[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20iOS-blue.svg)](https://github.com/Alexnnn/AstraAssistant)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)

---

## ✨ Features

- 🤖 **Local AI** with Ollama (Qwen2.5, Llama3.2 Vision, Nomic-Embed)
- 📱 **iPhone companion** — control your Mac from anywhere
- 🎙️ **Voice input/output** — STT + TTS (macOS / WaveSpeed / Qwen3)
- 🖼️ **Image generation & editing** — OpenAI DALL-E or WaveSpeed Seedream
- 🧠 **Long-term memory** — vector embeddings for personal context
- 📋 **Tasks & Calendar** — local task management + iCal integration
- 🌐 **Web search** — DuckDuckGo with smart LLM routing
- 🖥️ **Screen analysis** — capture and analyze macOS screen
- 📄 **File summarization** — PDF, TXT, JSON, CSV, Markdown

---

## 🏗️ Architecture

```mermaid
graph TD
    subgraph "iOS App (Companion)"
        iOS[SwiftUI Views]
        iOSVM[ViewModels]
        iOSClient[CompanionCommandClient]
    end
    
    subgraph "Firebase Cloud"
        Firestore[(Firestore Database)]
        Auth[Firebase Auth]
        Storage[Firebase Storage]
    end
    
    subgraph "macOS App (AI Engine)"
        MacBus[MacCommandBusService]
        MacExecutor[DefaultMacCommandExecutor]
        
        subgraph "Local Services"
            Ollama[Ollama Client]
            Memory[Vector Memory Store]
            Tasks[Task Store]
            Calendar[Calendar Service]
            WebSearch[Web Search Service]
            TTS[TTS Service]
            Images[Image Generation Service]
        end
        
        subgraph "External APIs"
            OpenAI[OpenAI API]
            WaveSpeed[WaveSpeed API]
            DuckDuckGo[DuckDuckGo]
        end
    end
    
    iOS -->|Send Command| Firestore
    iOS -->|Upload Files| Storage
    
    Firestore -->|Listen for Commands| MacBus
    MacBus -->|Execute| MacExecutor
    MacExecutor -->|Query| Ollama
    MacExecutor -->|Store/Retrieve| Memory
    MacExecutor -->|CRUD| Tasks
    MacExecutor -->|Read| Calendar
    
    MacExecutor -->|Generate Image| Images
    MacExecutor -->|TTS| TTS
    MacExecutor -->|Web Search| WebSearch
    
    Images -->|API Call| OpenAI
    Images -->|API Call| WaveSpeed
    TTS -->|API Call| WaveSpeed
    WebSearch -->|Scrape| DuckDuckGo
    
    MacExecutor -->|Write Response| Firestore
    Firestore -->|Poll for Response| iOS
    Storage -->|Download Audio/Images| iOS
📊 Data Flow
sequenceDiagram
    participant User as iPhone User
    participant iOS as iOS App
    participant Firebase as Firebase Firestore
    participant Mac as macOS App
    participant Ollama as Ollama LLM
    
    User->>iOS: Types message
    iOS->>Firebase: Write command (chat.send)
    Firebase-->>Mac: Listen for new commands
    Mac->>Ollama: Send prompt with context
    Ollama-->>Mac: Generate response
    Mac->>Firebase: Write response (status: done)
    Firebase-->>iOS: Poll and fetch response
    iOS-->>User: Display assistant reply
🔑 Key Design Decisions
1. Firebase as Communication Bridge
Decision: Use Firebase Firestore as the primary communication channel between iOS and macOS apps.

Why:

✅ No need for WebSockets or complex networking setup

✅ Built-in offline support

✅ Handles authentication (Anonymous Auth)

✅ Simple polling mechanism works well for command/response pattern

✅ Free tier sufficient for personal use

Tradeoff:

⚠️ Polling creates ~1-2 second latency (acceptable for AI responses)

⚠️ Requires internet connection

2. Local-First AI with Ollama
Decision: Run all AI models locally on Mac using Ollama, not in the cloud.

Why:

✅ Complete privacy — no data leaves your machine

✅ No API costs for chat, embeddings, or vision

✅ Works offline (after models are downloaded)

✅ User owns their data

Tradeoff:

⚠️ Requires powerful Mac (M1/M2/M3 recommended)

⚠️ Models take 4-8GB disk space each

⚠️ Slower than cloud APIs (but acceptable for assistant use)

3. Optional Cloud Services (API Keys)
Decision: Support cloud APIs for TTS and Image generation but make them optional.

Why:

✅ Users can choose between quality (cloud) and privacy (local)

✅ OpenAI/WaveSpeed provide superior image quality

✅ Voice cloning requires cloud TTS services

✅ APIs are not required — falls back to macOS TTS

Tradeoff:

⚠️ Requires API keys (users need to bring their own)

⚠️ Adds dependency on external services

4. Vector Memory with SQLite
Decision: Store embeddings and memory in SQLite with vector similarity search.

Why:

✅ No external vector database needed

✅ Fast enough for personal use (hundreds of memories)

✅ Simple backup/restore (single .sqlite file)

✅ SQLite is reliable and well-tested

Tradeoff:

⚠️ Not suitable for thousands of memories

⚠️ Cosine similarity is computed in memory

5. SwiftUI for Both Platforms
Decision: Use SwiftUI for both macOS and iOS apps, sharing ViewModels where possible.

Why:

✅ Single language (Swift) for both platforms

✅ Reusable business logic (Services, Models)

✅ Native performance on both platforms

✅ Easy to maintain with @MainActor

Tradeoff:

⚠️ Some platform-specific UI differences (NavigationView vs NavigationStack)

⚠️ macOS requires AppKit bridges for some features

6. QR Code Pairing
Decision: Use 6-digit codes and QR codes for device pairing.

Why:

✅ Simple UX — scan or type code

✅ No need for NFC or Bluetooth

✅ Works over internet (no local network required)

✅ Firebase ensures unique codes with expiry

Tradeoff:

⚠️ Code is transmitted in plain text (short-lived, so acceptable)

⚠️ Requires Firebase internet connection

7. Command/Response Pattern
Decision: Use asynchronous command/response pattern instead of real-time streaming.

Why:

✅ Simple to implement and debug

✅ Works well with Firestore's listening mechanism

✅ Natural for AI responses (which take time)

✅ iOS can show loading states

Tradeoff:

⚠️ No streaming for chat (user sees full response at once)

⚠️ Polling adds overhead

8. Keychain for API Keys
Decision: Store API keys (OpenAI, WaveSpeed) in macOS Keychain.

Why:

✅ Secure — keys never stored in UserDefaults or code

✅ macOS Keychain syncs across devices

✅ Accessible only to your app

✅ Industry best practice

Tradeoff:

⚠️ Slightly more complex than UserDefaults

⚠️ Requires proper Keychain entitlements

9. Local TTS with Python Bridge
Decision: Support Local Qwen3 TTS via Python script execution.

Why:

✅ Free, high-quality voice cloning

✅ Runs completely offline

✅ Supports voice cloning, custom voices, and voice design

✅ User retains control over TTS quality

Tradeoff:

⚠️ Requires Python environment setup

⚠️ Process spawning adds latency (2-5 seconds)

⚠️ More complex to debug

10. Anonymous Firebase Auth
Decision: Use Firebase Anonymous Authentication for all users.

Why:

✅ No login required — immediate access

✅ Each device gets unique UID

✅ Works with Firestore security rules

✅ Simple to implement

Tradeoff:

⚠️ Users can't restore data across devices (except via pairing)

⚠️ Limited Firebase security rules (no user management)

🚀 Quick Start
Prerequisites
macOS 14+ (Sonoma) for Mac app

iOS 17+ for iPhone app

Ollama installed on Mac

Firebase account (free tier works)

1. Clone the repository
bash
git clone https://github.com/Alexnnn/AstraAssistant.git
cd AstraAssistant
2. Firebase Setup
Go to Firebase Console

Create a new project

Add iOS app and macOS app

Enable Anonymous Authentication (Authentication → Sign-in methods)

Download GoogleService-Info.plist for each app

Place them in respective Xcode project folders

3. Install Ollama Models
Open Terminal and run:

bash
# Start Ollama
ollama serve

# Pull models (in another terminal)
ollama pull qwen2.5:14b      # Chat model
ollama pull nomic-embed-text  # Memory embeddings
ollama pull llama3.2-vision   # Vision model
4. Run the apps
Open AstraAI/Astra AI Assistant.xcodeproj → Build & run

Open AstraCompanion/AstraCompanion.xcodeproj → Build & run on iPhone

📱 Usage
Pairing iPhone with Mac
On Mac: Settings → iPhone / iPad Pairing → Generate Code

On iPhone: Enter the 6-digit code or scan QR code

Your devices are now connected! 🎉

Chat Commands
Command	Description
/help	Show all available commands
/search <query>	Search the web
/task <text>	Add a new task
/tasks	List all open tasks
/calendar today	Show today's events
/calendar add YYYY-MM-DD HH:mm | Title	Add calendar event
/now	Current date and time
Voice Modes
Manual — press button to start/stop listening

Push-to-Talk — hold button to speak

Hold-to-Talk — hold and release to send

Continuous — always listening

Wake Phrase — say "Astra" or custom phrase

🔧 Configuration
Voice TTS Providers
macOS — built-in system voices (fastest)

WaveSpeed Qwen3 — external API with voice cloning

Local Qwen3 — run Python TTS locally on Mac

Image Providers
OpenAI — DALL-E / GPT-Image (requires API key)

WaveSpeed Seedream — v4.5 / v5.0 Pro (requires API key)

🧪 Diagnostics
Run diagnostics in Settings → "Run Diagnostics" to verify:

✅ Ollama is running

✅ Required models are installed

✅ Microphone & Speech permissions

✅ API keys are configured (if using cloud services)

📄 License
This project is licensed under the MIT License — see the LICENSE file for details.

🙏 Acknowledgements
Ollama — Local LLM runtime

Firebase — Communication & authentication

WaveSpeed — TTS & image generation API

DuckDuckGo — Web search

🤝 Contributing
Fork the repository

Create your feature branch (git checkout -b feature/amazing-feature)

Commit your changes (git commit -m 'Add amazing feature')

Push to the branch (git push origin feature/amazing-feature)

Open a Pull Request

📬 Contact
GitHub: @Alexnnn

Website: sunteame.com

Built with ❤️ using SwiftUI
