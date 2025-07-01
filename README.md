# Vox

> Fast MP4 audio transcription using native macOS frameworks

Vox is a native macOS command-line interface (CLI) application that extracts audio from MP4 video files and transcribes the audio content to text using Apple's native SpeechAnalyzer framework with fallback to cloud-based transcription services.

## Features

- 🏃‍♂️ **Fast Native Processing**: Uses Apple's SpeechAnalyzer for optimal performance
- 🔒 **Privacy First**: Local processing with optional cloud fallback
- 🎯 **Multiple Output Formats**: Supports TXT, SRT, and JSON outputs
- 🌐 **Universal Binary**: Optimized for both Intel and Apple Silicon Macs
- ⚡ **High Performance**: Process 30-minute videos in under 60 seconds on Apple Silicon
- 🛡️ **Fallback Support**: Optional cloud transcription via OpenAI or Rev.ai APIs

## Installation

```bash
# Coming soon to Homebrew
brew install your-tap/vox

# Manual installation
curl -L https://github.com/your-repo/vox/releases/latest/download/vox -o /usr/local/bin/vox
chmod +x /usr/local/bin/vox
```

## System Requirements

### Minimum Requirements
- macOS 12.0 (Monterey) or later
- Intel x86_64 or Apple Silicon arm64
- 2GB RAM available
- 100MB free space

### Recommended Requirements
- macOS 13.0 (Ventura) or later
- Apple Silicon for optimal performance
- 4GB RAM available
- 500MB free space for temporary files

## Usage

### Basic Usage

```bash
# Basic transcription
vox video.mp4

# Custom output file
vox video.mp4 -o transcript.txt

# Generate subtitles
vox video.mp4 --format srt

# Batch processing
vox *.mp4
```

### Advanced Options

```bash
# Specify language
vox lecture.mp4 --language en-US

# Force cloud transcription
vox interview.mp4 --force-cloud --fallback-api openai

# Include timestamps
vox presentation.mp4 --timestamps --verbose
```

### Output Formats

- **TXT**: Plain text transcription
- **SRT**: Subtitle format with timestamps
- **JSON**: Detailed output with metadata and confidence scores

### Command Line Options

```bash
Options:
  -o, --output <path>        Output file path
  -f, --format <format>      Output format: txt, srt, json
  -l, --language <code>      Language code (e.g., en-US, es-ES)
  --fallback-api <provider>  Fallback API: openai, revai
  --api-key <key>           API key for fallback service
  -v, --verbose             Enable verbose output
  --force-cloud             Force cloud transcription (skip native)
  --timestamps              Include timestamps in output
  -h, --help               Show help information
```

## Examples

### Basic Transcription
```bash
vox conference.mp4
# Output: conference.txt with transcribed text
```

### Subtitle Generation
```bash
vox movie.mp4 --format srt
# Output: movie.srt with timestamped subtitles
```

### Detailed JSON Output
```bash
vox interview.mp4 --format json --timestamps
# Output: interview.json with detailed transcription data
```

## Performance

- **Apple Silicon**: Process 30-minute video in < 60 seconds
- **Intel Mac**: Process 30-minute video in < 90 seconds
- **Memory Usage**: Peak usage < 1GB for typical files
- **File Support**: Up to 2GB files, 4 hours duration

## Privacy & Security

- Local processing by default using native frameworks
- Optional cloud fallback with explicit user consent
- Secure handling of API keys (environment variables only)
- Automatic cleanup of temporary files
- No persistent storage of audio or transcriptions

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
