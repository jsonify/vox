# Vox Deployment Guide

## Overview
This document provides comprehensive instructions for building, packaging, and distributing the Vox CLI application for macOS.

## Build Configuration

### System Requirements

#### Development Environment
- **Xcode**: 15.0 or later
- **macOS**: 13.0 (Ventura) or later for development
- **Swift**: 5.9 or later
- **Hardware**: Both Intel and Apple Silicon Macs for universal binary testing

#### Target Environment
- **Minimum macOS**: 12.0 (Monterey)
- **Supported Architectures**: Intel x86_64 and Apple Silicon arm64
- **Runtime Dependencies**: None (statically linked)

### Project Configuration

#### Package.swift Setup
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "vox",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "vox", targets: ["vox"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "vox",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Crypto", package: "swift-crypto")
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableUpcomingFeature("ConciseMagicFile"),
                .enableUpcomingFeature("ForwardTrailingClosures"),
                .enableUpcomingFeature("ImplicitOpenExistentials"),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "VoxTests",
            dependencies: ["vox"],
            resources: [
                .copy("TestResources/")
            ]
        )
    ]
)
```

#### Build Settings
```bash
# Universal Binary Configuration
ARCHS = arm64 x86_64
VALID_ARCHS = arm64 x86_64
MACOSX_DEPLOYMENT_TARGET = 12.0
SWIFT_VERSION = 5.9

# Release Optimization
SWIFT_OPTIMIZATION_LEVEL = -O
SWIFT_COMPILATION_MODE = wholemodule
GCC_OPTIMIZATION_LEVEL = s
DEAD_CODE_STRIPPING = YES
STRIP_INSTALLED_PRODUCT = YES
COPY_PHASE_STRIP = YES
```

## Build Process

### Development Build
```bash
# Standard development build
swift build

# Debug build with verbose output
swift build --verbose

# Clean build
swift package clean
swift build

# Build specific configuration
swift build -c debug
swift build -c release
```

### Release Build Process

#### Step 1: Prepare for Release
```bash
# Update version in source code
# Update CHANGELOG.md
# Commit all changes
git add .
git commit -m "Prepare for release v1.0.0"
git tag v1.0.0
```

#### Step 2: Build Universal Binary
```bash
#!/bin/bash
# build-universal.sh

set -e

# Configuration
PROJECT_NAME="vox"
BUILD_DIR=".build"
RELEASE_DIR="release"
VERSION=$(git describe --tags --always)

echo "Building Vox v${VERSION} Universal Binary..."

# Clean previous builds
swift package clean
rm -rf ${RELEASE_DIR}
mkdir -p ${RELEASE_DIR}

# Build for Apple Silicon (arm64)
echo "Building for Apple Silicon (arm64)..."
swift build -c release --arch arm64

# Build for Intel (x86_64)
echo "Building for Intel (x86_64)..."
swift build -c release --arch x86_64

# Create universal binary
echo "Creating universal binary..."
lipo -create -output ${RELEASE_DIR}/${PROJECT_NAME} \
    ${BUILD_DIR}/arm64-apple-macosx/release/${PROJECT_NAME} \
    ${BUILD_DIR}/x86_64-apple-macosx/release/${PROJECT_NAME}

# Verify universal binary
echo "Verifying universal binary..."
lipo -info ${RELEASE_DIR}/${PROJECT_NAME}
file ${RELEASE_DIR}/${PROJECT_NAME}

# Test the binary
echo "Testing universal binary..."
./${RELEASE_DIR}/${PROJECT_NAME} --help

echo "Universal binary created successfully: ${RELEASE_DIR}/${PROJECT_NAME}"
```

#### Step 3: Code Signing (Optional)
```bash
# Sign the binary for distribution
codesign --sign "Developer ID Application: Your Name" \
         --options runtime \
         --timestamp \
         release/vox

# Verify signature
codesign --verify --verbose release/vox
spctl --assess --verbose release/vox
```

#### Step 4: Create Distribution Package
```bash
#!/bin/bash
# package-release.sh

VERSION=$(git describe --tags --always)
PACKAGE_NAME="vox-${VERSION}-macos-universal"
PACKAGE_DIR="packages/${PACKAGE_NAME}"

# Create package directory
mkdir -p ${PACKAGE_DIR}

# Copy binary
cp release/vox ${PACKAGE_DIR}/

# Create installation script
cat > ${PACKAGE_DIR}/install.sh << 'EOF'
#!/bin/bash
set -e

INSTALL_DIR="/usr/local/bin"
BINARY_NAME="vox"

echo "Installing Vox CLI..."

# Check if install directory exists
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Creating $INSTALL_DIR directory..."
    sudo mkdir -p "$INSTALL_DIR"
fi

# Copy binary
echo "Copying vox to $INSTALL_DIR..."
sudo cp "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
sudo chmod +x "$INSTALL_DIR/$BINARY_NAME"

# Verify installation
if command -v vox >/dev/null 2>&1; then
    echo "✅ Vox installed successfully!"
    echo "Try: vox --help"
else
    echo "⚠️  Vox installed but not found in PATH."
    echo "Add $INSTALL_DIR to your PATH or use full path: $INSTALL_DIR/vox"
fi
EOF

chmod +x ${PACKAGE_DIR}/install.sh

# Copy documentation
cp README.md ${PACKAGE_DIR}/
cp docs/USAGE.md ${PACKAGE_DIR}/ 2>/dev/null || echo "USAGE.md not found, skipping..."

# Create uninstall script
cat > ${PACKAGE_DIR}/uninstall.sh << 'EOF'
#!/bin/bash
set -e

INSTALL_DIR="/usr/local/bin"
BINARY_NAME="vox"

echo "Uninstalling Vox CLI..."

if [ -f "$INSTALL_DIR/$BINARY_NAME" ]; then
    sudo rm "$INSTALL_DIR/$BINARY_NAME"
    echo "✅ Vox uninstalled successfully!"
else
    echo "⚠️  Vox not found in $INSTALL_DIR"
fi
EOF

chmod +x ${PACKAGE_DIR}/uninstall.sh

# Create archive
cd packages
tar -czf "${PACKAGE_NAME}.tar.gz" "${PACKAGE_NAME}"
zip -r "${PACKAGE_NAME}.zip" "${PACKAGE_NAME}"
cd ..

echo "Distribution packages created:"
echo "  packages/${PACKAGE_NAME}.tar.gz"
echo "  packages/${PACKAGE_NAME}.zip"
```

## Distribution Methods

### 1. Direct Download (GitHub Releases)

#### GitHub Actions Release Workflow
```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build-and-release:
    runs-on: macos-latest
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Setup Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: '15.0'
        
    - name: Build Universal Binary
      run: |
        chmod +x scripts/build-universal.sh
        ./scripts/build-universal.sh
        
    - name: Create Distribution Package
      run: |
        chmod +x scripts/package-release.sh
        ./scripts/package-release.sh
        
    - name: Create Release
      uses: softprops/action-gh-release@v1
      with:
        files: |
          packages/*.tar.gz
          packages/*.zip
        body: |
          ## Vox ${{ github.ref_name }}
          
          ### Installation
          ```bash
          # Download and extract
          curl -L https://github.com/your-username/vox/releases/download/${{ github.ref_name }}/vox-${{ github.ref_name }}-macos-universal.tar.gz | tar -xz
          
          # Install
          cd vox-*/
          ./install.sh
          ```
          
          ### Usage
          ```bash
          vox video.mp4                    # Basic transcription
          vox video.mp4 -o transcript.txt  # Custom output
          vox video.mp4 --format srt       # Subtitle format
          ```
          
          ### What's New
          - See CHANGELOG.md for details
        draft: false
        prerelease: false
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### 2. Homebrew Distribution

#### Create Homebrew Formula
```ruby
# Formula/vox.rb
class Vox < Formula
  desc "Fast MP4 audio transcription using native macOS frameworks"
  homepage "https://github.com/your-username/vox"
  url "https://github.com/your-username/vox/releases/download/v1.0.0/vox-v1.0.0-macos-universal.tar.gz"
  sha256 "YOUR_SHA256_HERE"
  license "MIT"
  
  depends_on :macos
  depends_on macos: :monterey
  
  def install
    bin.install "vox"
  end
  
  test do
    system "#{bin}/vox", "--help"
  end
end
```

#### Homebrew Tap Setup
```bash
# Create homebrew tap repository
mkdir homebrew-vox
cd homebrew-vox

# Create Formula directory
mkdir Formula
cp vox.rb Formula/

# Initialize git repository
git init
git add .
git commit -m "Initial Vox formula"
git remote add origin https://github.com/your-username/homebrew-vox.git
git push -u origin main
```

#### User Installation via Homebrew
```bash
# Add tap
brew tap your-username/vox

# Install vox
brew install vox

# Upgrade
brew upgrade vox

# Uninstall
brew uninstall vox
```

### 3. Manual Installation

#### Installation Instructions
```bash
# Method 1: Direct download and install
curl -L https://github.com/your-username/vox/releases/latest/download/vox-macos-universal.tar.gz | tar -xz
cd vox-*/
./install.sh

# Method 2: Build from source
git clone https://github.com/your-username/vox.git
cd vox
swift build -c release
sudo cp .build/release/vox /usr/local/bin/

# Method 3: Direct binary download
curl -L -o vox https://github.com/your-username/vox/releases/latest/download/vox-macos-universal
chmod +x vox
sudo mv vox /usr/local/bin/
```

## Testing and Validation

### Pre-Release Testing Checklist

#### Architecture Testing
```bash
# Test on Apple Silicon
arch -arm64 vox --help
arch -arm64 vox sample.mp4

# Test on Intel (via Rosetta if needed)
arch -x86_64 vox --help
arch -x86_64 vox sample.mp4

# Verify universal binary
lipo -info vox
# Should output: Architectures in the fat file: vox are: x86_64 arm64
```

#### Functionality Testing
```bash
# Test basic functionality
vox --help
vox --version

# Test with sample files
vox tests/sample_short.mp4
vox tests/sample_long.mp4 --format srt
vox tests/sample_multilingual.mp4 --format json

# Test error conditions
vox nonexistent.mp4  # Should show helpful error
vox tests/corrupted.mp4  # Should handle gracefully

# Test output formats
vox sample.mp4 -o output.txt
vox sample.mp4 -o output.srt --format srt
vox sample.mp4 -o output.json --format json --timestamps
```

#### Performance Validation
```bash
# Benchmark performance
time vox tests/benchmark_30min.mp4

# Memory usage monitoring
/usr/bin/time -l vox tests/large_file.mp4

# Stress testing
for i in {1..10}; do
    vox tests/sample.mp4 -o "output_$i.txt" &
done
wait
```

### Automated Testing Pipeline

#### CI/CD Configuration
```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    strategy:
      matrix:
        os: [macos-13, macos-14]
        
    runs-on: ${{ matrix.os }}
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Setup Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: '15.0'
        
    - name: Cache Swift Package Manager
      uses: actions/cache@v3
      with:
        path: .build
        key: ${{ runner.os }}-spm-${{ hashFiles('Package.resolved') }}
        restore-keys: |
          ${{ runner.os }}-spm-
          
    - name: Build
      run: swift build --verbose
      
    - name: Run CI Tests
      run: swift test --filter CITests --verbose
      
    - name: Run Integration Tests
      run: swift test --filter IntegrationTests
      if: runner.os == 'macOS'
      
    - name: Build Release
      run: swift build -c release
      
    - name: Test Release Binary
      run: |
        .build/release/vox --help
        .build/release/vox --version
```

## Distribution Security

### Code Signing

#### Developer ID Setup
```bash
# List available certificates
security find-identity -v -p codesigning

# Sign the binary
codesign --sign "Developer ID Application: Your Name (TEAM_ID)" \
         --options runtime \
         --timestamp \
         --verbose \
         vox

# Verify signing
codesign --verify --deep --strict --verbose=2 vox
spctl --assess --type execute --verbose vox
```

#### Notarization (for Gatekeeper)
```bash
# Create app bundle for notarization
mkdir -p Vox.app/Contents/MacOS
cp vox Vox.app/Contents/MacOS/
cp Info.plist Vox.app/Contents/

# Sign the app bundle
codesign --sign "Developer ID Application: Your Name" \
         --options runtime \
         --timestamp \
         --deep \
         Vox.app

# Create ZIP for notarization
ditto -c -k --keepParent Vox.app Vox.zip

# Submit for notarization
xcrun notarytool submit Vox.zip \
    --apple-id "your-apple-id@example.com" \
    --password "app-specific-password" \
    --team-id "TEAM_ID" \
    --wait

# Staple the notarization
xcrun stapler staple Vox.app
```

### Checksum Verification
```bash
# Generate checksums for distribution
shasum -a 256 vox-v1.0.0-macos-universal.tar.gz > SHA256SUMS
shasum -a 256 vox-v1.0.0-macos-universal.zip >> SHA256SUMS

# Sign checksums
gpg --armor --detach-sign SHA256SUMS
```

## Environment Configuration

### Environment Variables
```bash
# Runtime configuration
export OPENAI_API_KEY="your-openai-key"
export REVAI_API_KEY="your-revai-key"
export VOX_VERBOSE="true"
export VOX_DEFAULT_FORMAT="srt"

# Build-time configuration
export SWIFT_VERSION="5.9"
export MACOSX_DEPLOYMENT_TARGET="12.0"
```

### Configuration Files
```bash
# ~/.voxrc (optional configuration file)
default_format=txt
verbose=false
fallback_api=openai
include_timestamps=true
```

## Troubleshooting Deployment

### Common Build Issues

#### Swift Package Manager Issues
```bash
# Clear package cache
swift package reset
rm -rf .build
swift package resolve

# Update dependencies
swift package update

# Resolve dependency conflicts
swift package show-dependencies
```

#### Architecture Issues
```bash
# Check current architecture
uname -m  # arm64 or x86_64

# Force specific architecture build
swift build -c release --arch arm64
swift build -c release --arch x86_64

# Debug lipo issues
lipo -detailed_info vox
otool -L vox  # Check linked libraries
```

#### Code Signing Issues
```bash
# Check certificate validity
security find-identity -v -p codesigning

# Reset keychain if needed
security delete-keychain ~/Library/Keychains/login.keychain
security create-keychain -p "" ~/Library/Keychains/login.keychain
security default-keychain -s ~/Library/Keychains/login.keychain

# Import certificate
security import certificate.p12 -k ~/Library/Keychains/login.keychain
```

### Runtime Issues

#### Permission Problems
```bash
# Fix installation permissions
sudo chown -R $(whoami) /usr/local/bin/vox
chmod +x /usr/local/bin/vox

# Check PATH
echo $PATH | grep -q "/usr/local/bin" || echo "Add /usr/local/bin to PATH"
```

#### Library Dependencies
```bash
# Check dynamic library dependencies
otool -L /usr/local/bin/vox

# Verify system frameworks
ls /System/Library/Frameworks/AVFoundation.framework
ls /System/Library/Frameworks/Speech.framework
```

## Maintenance and Updates

### Version Management
```bash
# Update version in source code
# Sources/vox/Version.swift
public let voxVersion = "1.0.1"

# Update Package.swift if needed
# Update CHANGELOG.md
# Update documentation
```

### Release Process
```bash
#!/bin/bash
# release.sh - Automated release script

VERSION=${1:-$(date +%Y.%m.%d)}

echo "Preparing release v${VERSION}..."

# Update version
sed -i '' "s/voxVersion = \".*\"/voxVersion = \"${VERSION}\"/" Sources/vox/Version.swift

# Run tests
swift test --filter CITests

# Build and package
./scripts/build-universal.sh
./scripts/package-release.sh

# Create git tag
git add .
git commit -m "Release v${VERSION}"
git tag "v${VERSION}"
git push origin main
git push origin "v${VERSION}"

echo "Release v${VERSION} complete!"
echo "GitHub Actions will handle the rest."
```

### Backward Compatibility
- Maintain command-line interface compatibility
- Provide migration guides for breaking changes
- Support deprecated options with warnings
- Document API changes in CHANGELOG.md

## Deployment Checklist

### Pre-Release
- [ ] All tests pass on CI
- [ ] Performance benchmarks meet targets
- [ ] Universal binary builds successfully
- [ ] Code signing works without errors
- [ ] Documentation is up to date
- [ ] CHANGELOG.md is updated

### Release
- [ ] GitHub release created with artifacts
- [ ] Homebrew formula updated
- [ ] Installation instructions tested
- [ ] Binary signatures verified
- [ ] Download links work correctly

### Post-Release
- [ ] Monitor issue reports
- [ ] Verify installation success
- [ ] Update documentation as needed
- [ ] Plan next release cycle

This comprehensive deployment guide ensures reliable, secure distribution of the Vox CLI application across different channels while maintaining high quality and user experience standards.