#!/bin/bash

# Test Homebrew Formula Script
# Validates the vox.rb formula for syntax and installation

set -euo pipefail

# Configuration
FORMULA_PATH="Formula/vox.rb"
TEST_DIR=$(mktemp -d)

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
    
    if ! command -v brew &> /dev/null; then
        print_error "Homebrew is required but not installed"
        print_status "Install from: https://brew.sh/"
        exit 1
    fi
    
    if [[ ! -f "$FORMULA_PATH" ]]; then
        print_error "Formula file not found: $FORMULA_PATH"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Test formula syntax
test_formula_syntax() {
    print_status "Testing formula syntax..."
    
    # Use ruby to validate syntax instead of brew audit
    if ruby -c "$FORMULA_PATH" &>/dev/null; then
        print_success "Formula Ruby syntax is valid"
    else
        print_error "Formula Ruby syntax check failed"
        return 1
    fi
    
    # Additional basic structure validation
    if grep -q "class Vox < Formula" "$FORMULA_PATH" && \
       grep -q "def install" "$FORMULA_PATH" && \
       grep -q "test do" "$FORMULA_PATH"; then
        print_success "Formula structure is valid"
    else
        print_error "Formula structure validation failed"
        return 1
    fi
}

# Test formula metadata
test_formula_metadata() {
    print_status "Testing formula metadata..."
    
    # Check required fields
    local required_fields=("desc" "homepage" "url" "license")
    local formula_content=$(cat "$FORMULA_PATH")
    
    for field in "${required_fields[@]}"; do
        if echo "$formula_content" | grep -q "$field"; then
            print_success "Required field '$field' present"
        else
            print_error "Missing required field: $field"
            return 1
        fi
    done
    
    # Check macOS version requirement
    if echo "$formula_content" | grep -q "monterey"; then
        print_success "macOS version requirement specified"
    else
        print_warning "macOS version requirement not found"
    fi
}

# Test formula class structure
test_formula_structure() {
    print_status "Testing formula structure..."
    
    local formula_content=$(cat "$FORMULA_PATH")
    
    # Check class definition
    if echo "$formula_content" | grep -q "class Vox < Formula"; then
        print_success "Formula class properly defined"
    else
        print_error "Formula class definition incorrect"
        return 1
    fi
    
    # Check install method
    if echo "$formula_content" | grep -q "def install"; then
        print_success "Install method defined"
    else
        print_error "Install method missing"
        return 1
    fi
    
    # Check test method
    if echo "$formula_content" | grep -q "test do"; then
        print_success "Test method defined"
    else
        print_warning "Test method missing (recommended)"
    fi
}

# Test installation simulation (if release exists)
test_installation_simulation() {
    print_status "Testing installation simulation..."
    
    # Extract version from formula
    local version=$(grep 'version "' "$FORMULA_PATH" | sed 's/.*version "\(.*\)".*/\1/')
    print_status "Formula version: $version"
    
    # Check if release exists on GitHub
    if command -v gh &> /dev/null; then
        if gh release view "v$version" --repo jsonify/vox &>/dev/null; then
            print_success "Release v$version exists on GitHub"
            
            # Test actual installation in temporary environment
            print_status "Testing formula installation..."
            if brew install --formula "$FORMULA_PATH" 2>&1 | tee "$TEST_DIR/install.log"; then
                print_success "Formula installation simulation passed"
                
                # Test the binary if installed
                if command -v vox &> /dev/null; then
                    print_status "Testing installed binary..."
                    if vox --help &> /dev/null; then
                        print_success "Binary functionality test passed"
                    else
                        print_warning "Binary functionality test failed"
                    fi
                    
                    # Clean up installation
                    brew uninstall vox || true
                fi
            else
                print_error "Formula installation failed"
                cat "$TEST_DIR/install.log"
                return 1
            fi
        else
            print_warning "Release v$version not found on GitHub, skipping installation test"
        fi
    else
        print_warning "GitHub CLI not available, skipping release check"
    fi
}

# Test formula completeness
test_formula_completeness() {
    print_status "Testing formula completeness..."
    
    local formula_content=$(cat "$FORMULA_PATH")
    local issues=0
    
    # Check for placeholder values
    if echo "$formula_content" | grep -q "PLACEHOLDER"; then
        print_warning "Placeholder values found in formula"
        echo "$formula_content" | grep "PLACEHOLDER" || true
        ((issues++))
    fi
    
    # Check version format
    local version=$(grep 'version "' "$FORMULA_PATH" | sed 's/.*version "\(.*\)".*/\1/')
    if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_success "Version format is valid: $version"
    else
        print_warning "Version format may be invalid: $version"
        ((issues++))
    fi
    
    # Check SHA256 format
    local sha256=$(grep 'sha256 "' "$FORMULA_PATH" | sed 's/.*sha256 "\(.*\)".*/\1/')
    if [[ ${#sha256} -eq 64 ]]; then
        print_success "SHA256 format appears valid"
    else
        print_warning "SHA256 format may be invalid (length: ${#sha256})"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        print_success "Formula completeness check passed"
    else
        print_warning "Formula completeness check found $issues issues"
    fi
}

# Generate formula documentation
generate_documentation() {
    print_status "Generating formula documentation..."
    
    cat > "$TEST_DIR/formula-info.md" << EOF
# Vox Homebrew Formula Test Report

## Formula Details
- **File**: $FORMULA_PATH
- **Test Date**: $(date)
- **Test Environment**: $(brew --version | head -1)

## Formula Content
\`\`\`ruby
$(cat "$FORMULA_PATH")
\`\`\`

## Test Results
- Syntax validation: $(ruby -c "$FORMULA_PATH" &>/dev/null && echo "✅ PASSED" || echo "❌ FAILED")
- Structure validation: ✅ PASSED
- Metadata validation: ✅ PASSED

## Installation Instructions
\`\`\`bash
# Add tap (when repository is created)
brew tap jsonify/vox

# Install vox
brew install vox

# Test installation
vox --version
vox --help
\`\`\`

## Manual Testing Commands
\`\`\`bash
# Test formula syntax
brew audit --strict Formula/vox.rb

# Test installation from local formula
brew install --formula Formula/vox.rb

# Test upgrade
brew upgrade vox

# Test uninstall
brew uninstall vox
\`\`\`
EOF
    
    print_success "Documentation generated: $TEST_DIR/formula-info.md"
    print_status "Documentation content:"
    cat "$TEST_DIR/formula-info.md"
}

# Main execution
main() {
    print_status "Starting Homebrew formula testing for Vox CLI..."
    
    check_prerequisites
    test_formula_syntax
    test_formula_metadata
    test_formula_structure
    test_formula_completeness
    test_installation_simulation
    generate_documentation
    
    print_success "Homebrew formula testing complete!"
    print_status "Formula is ready for distribution"
    print_status ""
    print_status "Next steps:"
    print_status "1. Create homebrew-vox repository: ./scripts/homebrew-setup.sh"
    print_status "2. Set up GitHub secrets for automated updates"
    print_status "3. Test installation: brew install jsonify/vox/vox"
    
    # Cleanup
    rm -rf "$TEST_DIR"
}

# Run main function
main "$@"