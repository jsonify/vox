# Vox - Audio Transcription CLI

[![CI](https://github.com/jsonify/vox/actions/workflows/ci.yml/badge.svg)](https://github.com/jsonify/vox/actions/workflows/ci.yml)
[![Release](https://github.com/jsonify/vox/actions/workflows/release.yml/badge.svg)](https://github.com/jsonify/vox/actions/workflows/release.yml)
[![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://support.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Fast, private, and accurate MP4 audio transcription using native macOS frameworks.

## ✨ Features

- **🚀 Lightning Fast** - Optimized for Apple Silicon, works great on Intel Macs
- **🔒 Privacy First** - Local processing with optional cloud fallback
- **📱 Native macOS** - Uses Apple's SpeechAnalyzer framework for best performance
- **📄 Multiple Formats** - Export as TXT, SRT subtitles, or structured JSON
- **⏱️ Timestamps** - Precise timing information for all transcriptions
- **🌐 Cloud Fallback** - OpenAI Whisper and Rev.ai integration when needed
- **🎯 Simple CLI** - Intuitive command-line interface designed for speed

## 🚀 Quick Start

### Installation

#### Homebrew (Recommended)
```bash
brew tap jsonify/vox
brew install vox
```

#### Direct Download
```bash
curl -L https://github.com/jsonify/vox/releases/latest/download/vox-macos-universal.tar.gz | tar -xz
cd vox-*/
./install.sh
```

#### Build from Source
```bash
git clone https://github.com/jsonify/vox.git
cd vox
swift build -c release
sudo cp .build/release/vox /usr/local/bin/
```

### Basic Usage

```bash
# Simple transcription
vox video.mp4

# Custom output file
vox video.mp4 -o transcript.txt

# Generate SRT subtitles
vox video.mp4 --format srt

# Include timestamps
vox video.mp4 --timestamps

# Verbose output
vox video.mp4 --verbose
```

### Advanced Usage

```bash
# Force specific language
vox video.mp4 --language en-US

# Use cloud fallback
export OPENAI_API_KEY="your-key"
vox video.mp4 --fallback-api openai

# JSON output with full metadata
vox video.mp4 --format json --timestamps

# Batch processing
vox *.mp4
```

## 📋 Requirements

- **macOS**: 12.0 (Monterey) or later
- **Architecture**: Intel x86_64 or Apple Silicon arm64
- **Memory**: 2GB+ RAM recommended
- **Storage**: 100MB+ free space for temporary files

## 🎛️ Command Reference

### Basic Options
| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--output` | `-o` | Output file path | `input_name.txt` |
| `--format` | `-f` | Output format (txt, srt, json) | `txt` |
| `--language` | `-l` | Language code (en-US, es-ES, etc.) | Auto-detect |
| `--verbose` | `-v` | Enable detailed output | `false` |
| `--help` | `-h` | Show help message | - |
| `--version` | | Show version information | - |

### Advanced Options
| Option | Description | Default |
|--------|-------------|---------|
| `--timestamps` | Include timestamps in output | `false` |
| `--force-cloud` | Skip native transcription, use cloud | `false` |
| `--fallback-api` | Cloud service (openai, revai) | None |
| `--api-key` | API key for cloud service | Environment variable |

### Output Formats

#### Plain Text (`.txt`)
```
This is the transcribed text from your video.
Multiple paragraphs are separated by line breaks.
```

#### Plain Text with Timestamps
```bash
vox video.mp4 --timestamps
```
```
[00:00:05] This is the transcribed text from your video.
[00:00:12] Multiple paragraphs are separated by line breaks.
```

#### SRT Subtitles (`.srt`)
```bash
vox video.mp4 --format srt
```
```
1
00:00:00,000 --> 00:00:05,000
This is the transcribed text from your video.

2
00:00:05,000 --> 00:00:12,000
Multiple paragraphs are separated by line breaks.
```

#### JSON (`.json`)
```bash
vox video.mp4 --format json
```
```json
{
  "transcription": "This is the transcribed text...",
  "language": "en-US",
  "confidence": 0.95,
  "duration": 120.5,
  "segments": [
    {
      "text": "This is the transcribed text from your video.",
      "startTime": 0.0,
      "endTime": 5.0,
      "confidence": 0.97
    }
  ],
  "metadata": {
    "engine": "native",
    "processingTime": 2.3,
    "voxVersion": "1.0.0",
    "timestamp": "2024-01-15T10:30:00Z"
  }
}
```

## ⚡ Performance

### Speed Benchmarks
| Architecture | 30-min Video | Ratio |
|-------------|--------------|-------|
| Apple Silicon M1/M2 | ~45 seconds | 40x real-time |
| Intel Core i7 | ~75 seconds | 24x real-time |

### Memory Usage
- **Typical**: 200-500MB for standard videos
- **Peak**: <1GB for large files
- **Temporary Storage**: Auto-cleaned after processing

## 🔒 Privacy & Security

Vox is designed with **privacy-first** principles:

- **🏠 Local Processing**: Native macOS transcription by default
- **🔐 No Data Storage**: Zero persistent storage of audio or transcripts
- **🛡️ Secure Cleanup**: Automatic secure deletion of temporary files
- **☁️ Optional Cloud**: Explicit consent required for cloud processing
- **🔑 Secure Keys**: API keys never stored persistently

See [SECURITY.md](docs/SECURITY.md) for detailed security information.

## 🌐 Cloud Integration

### OpenAI Whisper
```bash
export OPENAI_API_KEY="your-api-key"
vox video.mp4 --fallback-api openai
```

### Rev.ai
```bash
export REVAI_API_KEY="your-api-key" 
vox video.mp4 --fallback-api revai
```

### Intelligent Fallback
Vox automatically uses cloud services when:
- Native transcription confidence is low
- Audio quality is poor
- Specific language models are needed

## 🛠️ Development

### Project Structure
```
vox/
├── Sources/vox/           # Main application code
├── Tests/VoxTests/        # Test suite
├── docs/                  # Documentation
├── scripts/               # Build and deployment scripts
└── Package.swift          # Swift Package Manager configuration
```

### Building
```bash
# Development build
swift build

# Release build
swift build -c release

# Run tests
swift test

# Create universal binary
./scripts/build-universal.sh
```

### Contributing
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass (`swift test`)
6. Commit your changes (`git commit -m 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## 📚 Documentation

- [**Architecture**](docs/ARCHITECTURE.md) - System design and components
- [**Implementation**](docs/IMPLEMENTATION.md) - Development phases and tasks
- [**Testing**](docs/TESTING.md) - Testing strategy and guidelines
- [**Deployment**](docs/DEPLOYMENT.md) - Build and distribution process
- [**Security**](docs/SECURITY.md) - Security and privacy details
- [**Troubleshooting**](docs/TROUBLESHOOTING.md) - Common issues and solutions

## 🔧 Troubleshooting

### Common Issues

#### Permission Denied
```bash
sudo chmod +x /usr/local/bin/vox
```

#### Command Not Found
```bash
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

#### Audio Extraction Failed
```bash
# Install ffmpeg for additional format support
brew install ffmpeg
```

#### Low Transcription Quality
```bash
# Try cloud fallback for better accuracy
export OPENAI_API_KEY="your-key"
vox video.mp4 --fallback-api openai
```

### Getting Help
- 📖 Check the [documentation](docs/)
- 🐛 [Report bugs](https://github.com/jsonify/vox/issues)
- 💬 [Ask questions](https://github.com/jsonify/vox/discussions)
- 🔒 [Report security issues](mailto:security@vox-project.dev)

## 🎯 Roadmap

### Current Version (v1.0)
- ✅ Native macOS transcription
- ✅ Multiple output formats
- ✅ Cloud fallback integration
- ✅ Universal binary support

### Upcoming Features
- 🔄 **Batch Processing** - Process multiple files efficiently
- 🎤 **Real-time Transcription** - Live audio from microphone
- 👥 **Speaker Diarization** - Identify multiple speakers
- 🌍 **Translation** - Multi-language translation support
- 🖥️ **GUI Interface** - Optional graphical interface

### Future Enhancements
- 📱 Cross-platform support (Linux, Windows)
- 🔌 Plugin architecture for extensibility
- 📊 Advanced analytics and reporting
- 🤖 Custom AI model integration

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Apple** - For the excellent SpeechAnalyzer framework
- **Swift Community** - For the amazing tools and libraries
- **Contributors** - For making this project better

## 📊 Stats

![GitHub stars](https://img.shields.io/github/stars/jsonify/vox?style=social)
![GitHub forks](https://img.shields.io/github/forks/jsonify/vox?style=social)
![GitHub issues](https://img.shields.io/github/issues/jsonify/vox)
![GitHub last commit](https://img.shields.io/github/last-commit/jsonify/vox)

---

<div align="center">

**Made with ❤️ for the macOS community**

[Website](https://vox-project.dev) • [Documentation](docs/) • [Issues](https://github.com/jsonify/vox/issues) • [Discussions](https://github.com/jsonify/vox/discussions)

</div>
