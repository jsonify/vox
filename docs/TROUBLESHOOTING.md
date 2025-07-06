# Troubleshooting Guide

This guide helps you resolve common issues when using the Vox audio transcription CLI.

## Quick Fixes

### Command Not Found
```bash
# Error: vox: command not found
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### Permission Denied
```bash
# Error: permission denied
sudo chmod +x /usr/local/bin/vox
```

### Audio Extraction Failed
```bash
# Install ffmpeg for additional format support
brew install ffmpeg
```

## Installation Issues

### Homebrew Installation Failed
```bash
# If brew tap fails, try direct installation
curl -L https://github.com/jsonify/vox/releases/latest/download/vox-macos-universal.tar.gz | tar -xz
cd vox-*/
./install.sh
```

### Build from Source Failed
```bash
# Ensure you have the right Swift version
swift --version  # Should be 5.9+

# Clean and rebuild
swift package clean
swift build -c release
```

### Universal Binary Issues
```bash
# Check architecture compatibility
lipo -archs /usr/local/bin/vox
# Should show: arm64 x86_64
```

## Runtime Issues

### Transcription Quality Problems

#### Low Accuracy
```bash
# Try cloud fallback for better accuracy
export OPENAI_API_KEY="your-key"
vox video.mp4 --fallback-api openai

# Or specify language explicitly
vox video.mp4 --language en-US
```

#### Missing Words or Phrases
```bash
# Use verbose mode to debug
vox video.mp4 --verbose

# Check audio quality indicators in output
# Low confidence scores indicate poor audio
```

#### Wrong Language Detection
```bash
# Force specific language
vox video.mp4 --language es-ES  # Spanish
vox video.mp4 --language fr-FR  # French
vox video.mp4 --language de-DE  # German
```

### Audio Processing Errors

#### Unsupported Audio Format
```bash
# Error: Failed to extract audio
# Install ffmpeg for broader format support
brew install ffmpeg

# Verify ffmpeg installation
ffmpeg -version
```

#### Corrupted Audio Stream
```bash
# Test with a different file first
vox known_good_file.mp4

# If that works, the original file may be corrupted
# Try re-encoding the original file
ffmpeg -i problematic.mp4 -c:v copy -c:a aac fixed.mp4
vox fixed.mp4
```

#### Large File Processing
```bash
# For very large files (>2GB), ensure sufficient disk space
df -h /tmp

# Monitor memory usage during processing
vox large_file.mp4 --verbose
```

### Cloud Service Issues

#### API Key Problems
```bash
# Verify API key is set correctly
echo $OPENAI_API_KEY
echo $REVAI_API_KEY

# Test with explicit key
vox video.mp4 --fallback-api openai --api-key "your-key"
```

#### Network Connectivity
```bash
# Test internet connection
curl -I https://api.openai.com/v1/models

# Use verbose mode to see network requests
vox video.mp4 --fallback-api openai --verbose
```

#### Rate Limiting
```bash
# If you hit rate limits, wait and retry
# Or use a different cloud service
vox video.mp4 --fallback-api revai
```

### Output Format Issues

#### SRT Timing Problems
```bash
# Ensure timestamps are included
vox video.mp4 --format srt --timestamps

# Check original video duration
ffprobe -v quiet -show_entries format=duration -of csv=p=0 video.mp4
```

#### JSON Parsing Errors
```bash
# Validate JSON output
vox video.mp4 --format json | jq .

# If jq is not installed
brew install jq
```

#### File Permission Errors
```bash
# Error: Cannot write to output file
# Check directory permissions
ls -la /path/to/output/directory/

# Create output directory if needed
mkdir -p /path/to/output/
```

## Performance Issues

### Slow Processing

#### Apple Silicon Optimization
```bash
# Verify you're running the arm64 version
file /usr/local/bin/vox
# Should show: Mach-O 64-bit executable arm64

# If not, reinstall with universal binary
```

#### Memory Constraints
```bash
# Monitor memory usage
vox video.mp4 --verbose

# Close other applications if memory is low
# Consider processing smaller chunks
```

#### Storage Issues
```bash
# Check available disk space
df -h /tmp

# Clean temporary files if needed
rm -rf /tmp/vox-*
```

### Hanging or Freezing

#### Process Monitoring
```bash
# Check if vox is running
ps aux | grep vox

# Kill hanging process
pkill -f vox
```

#### Debug Mode
```bash
# Run with maximum verbosity
vox video.mp4 --verbose 2>&1 | tee debug.log

# Review debug.log for stuck operations
```

## System Compatibility

### macOS Version Issues
```bash
# Check macOS version (requires 12.0+)
sw_vers

# Update macOS if needed
# System Settings > General > Software Update
```

### Architecture Compatibility
```bash
# Check your Mac's architecture
uname -m
# arm64 = Apple Silicon
# x86_64 = Intel

# Verify vox binary matches
file /usr/local/bin/vox
```

## Advanced Diagnostics

### Verbose Logging
```bash
# Enable detailed logging
export VOX_VERBOSE=1
vox video.mp4

# Or use command line flag
vox video.mp4 --verbose
```

### System Information
```bash
# Gather system info for bug reports
echo "=== System Information ==="
sw_vers
uname -a
vox --version
echo "=== Memory ==="
vm_stat
echo "=== Disk Space ==="
df -h
echo "=== Audio System ==="
system_profiler SPAudioDataType
```

### File Analysis
```bash
# Analyze problematic video files
ffprobe -v quiet -print_format json -show_streams video.mp4

# Check audio stream specifically
ffprobe -v quiet -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of csv=p=0 video.mp4
```

## Getting Help

### Before Reporting Issues

1. **Check the FAQ** - Common issues are documented above
2. **Test with sample file** - Verify vox works with a known good file
3. **Try cloud fallback** - Test if the issue is with native processing
4. **Update to latest version** - `brew upgrade vox` or download latest release

### Information to Include

When reporting issues, include:

```bash
# System information
vox --version
sw_vers
uname -a

# Error output
vox problematic.mp4 --verbose 2>&1 | tee error.log

# File information
ffprobe -v quiet -print_format json -show_streams problematic.mp4
```

### Contact Options

- **GitHub Issues**: https://github.com/jsonify/vox/issues
- **Discussions**: https://github.com/jsonify/vox/discussions
- **Security Issues**: security@vox-project.dev

### Community Resources

- **Documentation**: https://github.com/jsonify/vox/tree/main/docs
- **Examples**: https://github.com/jsonify/vox/tree/main/examples
- **Wiki**: https://github.com/jsonify/vox/wiki

## Frequently Asked Questions

### Q: Why is transcription slower than expected?
A: Ensure you're using the correct architecture binary (arm64 for Apple Silicon). Also check available memory and disk space.

### Q: Can I transcribe files other than MP4?
A: Currently only MP4 is supported. Use ffmpeg to convert other formats: `ffmpeg -i input.mov -c copy output.mp4`

### Q: How do I improve transcription accuracy?
A: Try cloud fallback services, specify the correct language, or ensure good audio quality in your source file.

### Q: Is there a file size limit?
A: No hard limit, but very large files (>2GB) may require more memory and processing time.

### Q: Can I use multiple API keys?
A: You can switch between services using `--fallback-api` but only one key is used per invocation.

### Q: How do I batch process files?
A: Use shell wildcards: `vox *.mp4` or write a script for more complex batch operations.

---

*For additional help, please check the [main documentation](../README.md) or open an issue on GitHub.*