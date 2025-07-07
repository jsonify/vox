#!/bin/bash

# Homebrew Tap Setup Script
# Creates and configures the homebrew-vox tap repository

set -euo pipefail

# Configuration
REPO_NAME="homebrew-vox"
GITHUB_USER="jsonify"
REPO_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
TEMP_DIR=$(mktemp -d)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is required but not installed"
        print_status "Install with: brew install gh"
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        print_error "Git is required but not installed"
        exit 1
    fi
    
    # Check if authenticated with GitHub
    if ! gh auth status &> /dev/null; then
        print_error "Not authenticated with GitHub CLI"
        print_status "Run: gh auth login"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Create the homebrew-vox repository
create_repository() {
    print_status "Creating homebrew-vox repository..."
    
    # Check if repository already exists
    if gh repo view "${GITHUB_USER}/${REPO_NAME}" &> /dev/null; then
        print_warning "Repository ${GITHUB_USER}/${REPO_NAME} already exists"
        read -p "Do you want to continue and update it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Exiting..."
            exit 0
        fi
    else
        # Create new repository
        gh repo create "${REPO_NAME}" \
            --public \
            --description "Homebrew tap for Vox CLI - Fast, private MP4 audio transcription" \
            --homepage "https://github.com/jsonify/vox"
        
        print_success "Repository created: https://github.com/${GITHUB_USER}/${REPO_NAME}"
    fi
}

# Set up repository structure
setup_repository_structure() {
    print_status "Setting up repository structure..."
    
    cd "$TEMP_DIR"
    
    # Clone or initialize repository
    if gh repo view "${GITHUB_USER}/${REPO_NAME}" &> /dev/null; then
        git clone "$REPO_URL"
        cd "$REPO_NAME"
    else
        print_error "Repository does not exist"
        exit 1
    fi
    
    # Create directory structure
    mkdir -p Formula
    mkdir -p .github/workflows
    
    # Copy formula from main repository
    if [[ -f "${GITHUB_WORKSPACE:-$(pwd)}/Formula/vox.rb" ]]; then
        cp "${GITHUB_WORKSPACE:-$(pwd)}/Formula/vox.rb" Formula/
    else
        print_warning "Formula not found in main repository, creating template..."
        create_formula_template
    fi
    
    # Create README
    create_readme
    
    # Create GitHub Actions workflow
    create_github_workflow
    
    # Create LICENSE
    create_license
    
    print_success "Repository structure created"
}

# Create formula template if not exists
create_formula_template() {
    cat > Formula/vox.rb << 'EOF'
class Vox < Formula
  desc "Fast, private, and accurate MP4 audio transcription using native macOS frameworks"
  homepage "https://github.com/jsonify/vox"
  url "https://github.com/jsonify/vox/releases/download/v#{version}/vox-#{version}-macos-universal.tar.gz"
  sha256 "PLACEHOLDER_SHA256_HASH"
  license "MIT"
  version "1.0.0"

  depends_on :macos => :monterey

  def install
    bin.install "vox"
    
    if File.exist?("docs/vox.1")
      man1.install "docs/vox.1"
    end
  end

  test do
    assert_match "vox", shell_output("#{bin}/vox --help")
    assert_match version.to_s, shell_output("#{bin}/vox --version")
  end
end
EOF
}

# Create README for tap repository
create_readme() {
    cat > README.md << 'EOF'
# Homebrew Tap for Vox CLI

Fast, private, and accurate MP4 audio transcription using native macOS frameworks.

## Installation

```bash
# Add tap and install
brew tap jsonify/vox
brew install vox

# Or install directly
brew install jsonify/vox/vox
```

## Usage

```bash
# Basic transcription
vox video.mp4

# Save to specific file
vox video.mp4 -o transcript.txt

# Include timestamps
vox video.mp4 --timestamps

# Verbose output
vox video.mp4 -v
```

## Requirements

- macOS 12.0+ (Monterey or later)
- Universal binary supports both Intel and Apple Silicon Macs

## Documentation

- [Main Project](https://github.com/jsonify/vox)
- [Documentation](https://github.com/jsonify/vox/tree/main/docs)
- [Issues](https://github.com/jsonify/vox/issues)

## License

MIT License - see [LICENSE](LICENSE) file for details.
EOF
}

# Create GitHub Actions workflow for the tap repository
create_github_workflow() {
    cat > .github/workflows/test-formula.yml << 'EOF'
name: Test Formula

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    strategy:
      matrix:
        os: [macos-12, macos-13, macos-14]
    runs-on: ${{ matrix.os }}
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Test formula syntax
      run: |
        brew audit --strict Formula/vox.rb
        
    - name: Test formula installation (if release exists)
      run: |
        # Only test if the version exists in releases
        VERSION=$(grep 'version "' Formula/vox.rb | sed 's/.*version "\(.*\)".*/\1/')
        if gh release view "v$VERSION" --repo jsonify/vox &>/dev/null; then
          brew install --formula Formula/vox.rb
          brew test vox
        else
          echo "Release v$VERSION not found, skipping installation test"
        fi
      env:
        HOMEBREW_NO_AUTO_UPDATE: 1
        GH_TOKEN: ${{ github.token }}
EOF
}

# Create LICENSE file
create_license() {
    cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2024 jsonify

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
}

# Commit and push changes
commit_and_push() {
    print_status "Committing and pushing changes..."
    
    git add .
    
    if git diff --cached --quiet; then
        print_warning "No changes to commit"
        return 0
    fi
    
    git config user.name "GitHub Actions Setup"
    git config user.email "noreply@github.com"
    
    git commit -m "Initial Homebrew tap setup

- Add vox.rb formula
- Add README with installation instructions
- Add GitHub Actions for testing
- Add MIT license"
    
    git push origin main
    
    print_success "Changes pushed to repository"
}

# Main execution
main() {
    print_status "Starting Homebrew tap setup for Vox CLI..."
    
    check_prerequisites
    create_repository
    setup_repository_structure
    commit_and_push
    
    print_success "Homebrew tap setup complete!"
    print_status "Repository: https://github.com/${GITHUB_USER}/${REPO_NAME}"
    print_status ""
    print_status "Users can now install with:"
    print_status "  brew tap jsonify/vox"
    print_status "  brew install vox"
    print_status ""
    print_status "Or directly:"
    print_status "  brew install jsonify/vox/vox"
    
    # Cleanup
    rm -rf "$TEMP_DIR"
}

# Run main function
main "$@"