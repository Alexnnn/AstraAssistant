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
┌─────────────────┐ ┌─────────────────┐
│ macOS App │ │ iOS App │
│ (AI Engine) │◄───────►│ (Companion) │
└────────┬────────┘ └────────┬────────┘
│ │
└──────────┬─────────────────┘
│
┌───────▼───────┐
│ Firebase │
│ Firestore │
└───────────────┘

### How it works

1. **iOS app** sends commands to Firebase Firestore
2. **macOS app** listens for commands and executes them
3. **macOS app** writes results back to Firebase
4. **iOS app** receives results and displays them

---

## 🚀 Quick Start

### Prerequisites

- macOS 14+ (Sonoma) for Mac app
- iOS 17+ for iPhone app
- [Ollama](https://ollama.com) installed on Mac
- Firebase account (free tier works)

### 1. Clone the repository

```bash
git clone https://github.com/yourusername/AstraAssistant.git
cd AstraAssistant

### 2. Firebase Setup

1. Go to Firebase Console
2. Create a new project
3. Add iOS app and macOS app
4. Enable Anonymous Authentication (Authentication → Sign-in methods)
5. Download GoogleService-Info.plist for each app
6. Place them in respective Xcode project folders

### 3. Install Ollama Models
Open Terminal and run:

# Start Ollama
ollama serve

# Pull models (in another terminal)
ollama pull qwen2.5:14b      # Chat model
ollama pull nomic-embed-text  # Memory embeddings
ollama pull llama3.2-vision   # Vision model

### 4. Run the apps

1. Open AstraAI/Astra AI Assistant.xcodeproj → Build & run
2. Open AstraCompanion/AstraCompanion.xcodeproj → Build & run on iPhone

📱 Usage
Pairing iPhone with Mac

1. On Mac: Settings → iPhone / iPad Pairing → Generate Code
2. On iPhone: Enter the 6-digit code or scan QR code
3. Your devices are now connected! 🎉

Chat Commands:
Command                                   	Description
/help	                                  Show all available commands
/search <query>	                        Search the web
/task <text>	                          Add a new task
/tasks	                                List all open tasks
/calendar today	                        Show today's events
/calendar add YYYY-MM-DD HH:mm | Title	Add calendar event
/now	                                  Current date and time

Voice Modes

* Manual — press button to start/stop listening
* Push-to-Talk — hold button to speak
* Hold-to-Talk — hold and release to send
* Continuous — always listening
* Wake Phrase — say "Astra" or custom phrase

🔧 Configuration

Voice TTS Providers
* macOS — built-in system voices (fastest)
* WaveSpeed Qwen3 — external API with voice cloning
* Local Qwen3 — run Python TTS locally on Mac

Image Providers
* OpenAI — DALL-E / GPT-Image (requires API key)
* WaveSpeed Seedream — v4.5 / v5.0 Pro (requires API key)

🧪 Diagnostics
Run diagnostics in Settings → "Run Diagnostics" to verify:
✅ Ollama is running
✅ Required models are installed
✅ Microphone & Speech permissions
✅ API keys are configured (if using cloud services)

📄 License
This project is licensed under the MIT License — see the LICENSE file for details.

🙏 Acknowledgements
- Ollama — Local LLM runtime
- WaveSpeed — TTS & image generation API
- DuckDuckGo — Web search

🤝 Contributing
1. Fork the repository
2. Create your feature branch (git checkout -b feature/amazing-feature)
3. Commit your changes (git commit -m 'Add amazing feature')
4. Push to the branch (git push origin feature/amazing-feature)
5. Open a Pull Request

📬 Contact
* GitHub: @Alexnnn
* https://sunteame.com/contact-us/

Built with ❤️ using SwiftUI
