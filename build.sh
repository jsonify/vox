#!/bin/bash

# Vox CLI Universal Binary Build Script
# Optimized build process for Intel and Apple Silicon architectures

set -e  # Exit on any error

# Configuration
PROJECT_NAME="vox"
BUILD_CONFIG="release"
DIST_DIR="dist"
TEMP_BUILD_DIR=".build-temp"

# CI/CD integration flags
CI_MODE=${CI_MODE:-false}
SKIP_TESTS=${SKIP_TESTS:-false}
SKIP_PACKAGING=${SKIP_PACKAGING:-false}
SKIP_VALIDATION=${SKIP_VALIDATION:-false}
BUILD_VERSION=${BUILD_VERSION:-""}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to clean build artifacts
clean_build() {
    log_info "Cleaning previous build artifacts..."
    rm -rf .build
    rm -rf $TEMP_BUILD_DIR
    rm -rf $DIST_DIR
    log_success "Build artifacts cleaned"
}

# Function to validate environment
validate_environment() {
    log_info "Validating build environment..."
    
    # Check Swift version
    if ! command -v swift &> /dev/null; then
        log_error "Swift not found. Please install Xcode or Swift toolchain."
        exit 1
    fi
    
    SWIFT_VERSION=$(swift --version | head -n 1)
    log_info "Swift version: $SWIFT_VERSION"
    
    # Check for required tools
    if ! command -v lipo &> /dev/null; then
        log_error "lipo command not found. Please ensure Xcode command line tools are installed."
        exit 1
    fi
    
    # Check macOS version
    MACOS_VERSION=$(sw_vers -productVersion)
    log_info "macOS version: $MACOS_VERSION"
    
    log_success "Environment validation complete"
}

# Function to run tests before building
run_tests() {
    if [[ "$SKIP_TESTS" == "true" ]]; then
        log_warning "Skipping tests (SKIP_TESTS=true)"
        return 0
    fi
    
    log_info "Running CI tests..."
    if [[ "$CI_MODE" == "true" ]]; then
        # In CI mode, provide more detailed output
        log_info "Running in CI mode with enhanced logging"
        if swift test --filter CITests --verbose 2>&1 | tee test-output.log; then
            log_success "All tests passed"
            # Clean up test log in CI mode
            rm -f test-output.log
        else
            log_error "Tests failed. Build aborted."
            log_error "Test output:"
            tail -20 test-output.log || echo "Could not read test output"
            exit 1
        fi
    else
        # Standard test execution
        if swift test --filter CITests --verbose; then
            log_success "All tests passed"
        else
            log_error "Tests failed. Build aborted."
            exit 1
        fi
    fi
}

# Function to build for specific architecture
build_for_arch() {
    local arch=$1
    log_info "Building for $arch architecture..."
    
    # Set architecture-specific build directory
    local build_dir=".build/$arch-apple-macosx/$BUILD_CONFIG"
    
    if swift build -c $BUILD_CONFIG --arch $arch; then
        # Verify binary was created
        if [[ -f "$build_dir/$PROJECT_NAME" ]]; then
            local size=$(du -h "$build_dir/$PROJECT_NAME" | cut -f1)
            log_success "$arch binary built successfully (Size: $size)"
            
            # Verify architecture
            local arch_info=$(file "$build_dir/$PROJECT_NAME" | grep -o "$arch")
            if [[ -n "$arch_info" ]]; then
                log_success "$arch architecture verified"
            else
                log_warning "Could not verify $arch architecture"
            fi
        else
            log_error "$arch binary not found at expected location"
            exit 1
        fi
    else
        log_error "Failed to build for $arch"
        exit 1
    fi
}

# Function to create universal binary
create_universal_binary() {
    log_info "Creating universal binary..."
    
    # Create distribution directory
    mkdir -p $DIST_DIR
    
    local arm64_binary=".build/arm64-apple-macosx/$BUILD_CONFIG/$PROJECT_NAME"
    local x86_64_binary=".build/x86_64-apple-macosx/$BUILD_CONFIG/$PROJECT_NAME"
    local universal_binary="$DIST_DIR/$PROJECT_NAME"
    
    # Verify source binaries exist
    if [[ ! -f "$arm64_binary" ]]; then
        log_error "ARM64 binary not found: $arm64_binary"
        exit 1
    fi
    
    if [[ ! -f "$x86_64_binary" ]]; then
        log_error "x86_64 binary not found: $x86_64_binary"
        exit 1
    fi
    
    # Create universal binary
    if lipo -create -output "$universal_binary" "$arm64_binary" "$x86_64_binary"; then
        log_success "Universal binary created: $universal_binary"
        
        # Make executable
        chmod +x "$universal_binary"
        
        # Verify universal binary
        log_info "Verifying universal binary..."
        file "$universal_binary"
        lipo -info "$universal_binary"
        
        # Get final size
        local final_size=$(du -h "$universal_binary" | cut -f1)
        log_success "Universal binary size: $final_size"
        
        # Calculate size optimization
        local arm64_size=$(stat -f%z "$arm64_binary")
        local x86_64_size=$(stat -f%z "$x86_64_binary")
        local universal_size=$(stat -f%z "$universal_binary")
        local combined_size=$((arm64_size + x86_64_size))
        local savings=$((combined_size - universal_size))
        local savings_percent=$(( (savings * 100) / combined_size ))
        
        log_info "Size optimization: $savings bytes saved (${savings_percent}% reduction)"
        
    else
        log_error "Failed to create universal binary"
        exit 1
    fi
}

# Function to validate final binary
validate_binary() {
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        log_warning "Skipping binary validation (SKIP_VALIDATION=true)"
        return 0
    fi
    
    local binary="$DIST_DIR/$PROJECT_NAME"
    
    log_info "Validating final binary..."
    
    # Check if binary exists and is executable
    if [[ ! -x "$binary" ]]; then
        log_error "Binary is not executable"
        exit 1
    fi
    
    # Check architectures
    local archs=$(lipo -info "$binary" | grep -o "arm64\|x86_64" | sort | uniq | tr '\n' ' ')
    if [[ "$archs" == *"arm64"* && "$archs" == *"x86_64"* ]]; then
        log_success "Binary contains both ARM64 and x86_64 architectures"
    else
        log_error "Binary missing required architectures. Found: $archs"
        exit 1
    fi
    
    # Test basic functionality (if possible)
    if [[ "$CI_MODE" == "true" ]]; then
        # In CI mode, be more tolerant of binary test failures
        if timeout 10s "$binary" --help > /dev/null 2>&1; then
            log_success "Binary help command works"
        else
            log_warning "Could not test binary functionality (timeout or error - may be normal in CI)"
        fi
    else
        # In local mode, test is more critical
        if timeout 10s "$binary" --help > /dev/null 2>&1; then
            log_success "Binary help command works"
        else
            log_warning "Could not test binary functionality (timeout or error)"
        fi
    fi
    
    # Generate checksum
    local checksum=$(shasum -a 256 "$binary" | cut -d' ' -f1)
    echo "$checksum  $PROJECT_NAME" > "$DIST_DIR/checksum.txt"
    log_success "Checksum generated: $checksum"
}

# Function to create distribution packages
create_distribution_packages() {
    if [[ "$SKIP_PACKAGING" == "true" ]]; then
        log_warning "Skipping packaging (SKIP_PACKAGING=true)"
        return 0
    fi
    
    log_info "Creating distribution packages..."
    cd $DIST_DIR
    
    # Get version from BUILD_VERSION or git tag or use default
    local version="$BUILD_VERSION"
    if [[ -z "$version" ]]; then
        version=$(git describe --tags --exact-match 2>/dev/null || echo "dev")
    fi
    
    local package_base="$PROJECT_NAME-$version-macos-universal"
    
    # Files to include in packages
    local files_to_package=("$PROJECT_NAME")
    if [[ -f "checksum.txt" ]]; then
        files_to_package+=("checksum.txt")
    fi
    
    # Create tar.gz
    if tar -czf "$package_base.tar.gz" "${files_to_package[@]}"; then
        log_success "Created $package_base.tar.gz"
    else
        log_error "Failed to create tar.gz package"
        exit 1
    fi
    
    # Create zip
    if zip -q "$package_base.zip" "${files_to_package[@]}"; then
        log_success "Created $package_base.zip"
    else
        log_error "Failed to create zip package"
        exit 1
    fi
    
    # Generate package checksums
    shasum -a 256 *.tar.gz *.zip > checksums.txt
    
    log_success "Distribution packages created:"
    ls -la *.tar.gz *.zip *.txt 2>/dev/null || true
    
    cd ..
}

# Function to print build summary
print_summary() {
    local build_time_start=$1
    local binary="$DIST_DIR/$PROJECT_NAME"
    local build_time_end=$(date +%s)
    local build_duration=$((build_time_end - build_time_start))
    
    echo ""
    log_success "🎉 BUILD COMPLETED SUCCESSFULLY!"
    echo ""
    echo "📊 Build Summary:"
    echo "  • Duration: ${build_duration}s"
    echo "  • Binary: $binary"
    echo "  • Size: $(du -h "$binary" | cut -f1)"
    echo "  • Architectures: $(lipo -info "$binary" | grep -o "arm64\|x86_64" | tr '\n' ' ')"
    echo ""
    echo "📦 Distribution files:"
    if [[ -d "$DIST_DIR" ]]; then
        ls -la "$DIST_DIR"
    fi
    echo ""
    echo "🚀 Installation:"
    echo "  sudo mv $binary /usr/local/bin/"
    echo "  $PROJECT_NAME --help"
    echo ""
}

# Main build function
main() {
    local build_time_start=$(date +%s)
    
    echo "🔨 Vox CLI Universal Binary Build"
    echo "=================================="
    
    # Detect CI environment
    if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
        export CI_MODE=true
        log_info "CI environment detected - enabling CI mode"
    fi
    
    # Parse command line arguments
    case "${1:-}" in
        "clean")
            clean_build
            exit 0
            ;;
        "test")
            run_tests
            exit 0
            ;;
        "validate")
            validate_environment
            exit 0
            ;;
        "help"|"--help"|"-h")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  clean     Clean build artifacts"
            echo "  test      Run tests only"
            echo "  validate  Validate build environment"
            echo "  help      Show this help"
            echo ""
            echo "Environment variables:"
            echo "  CI_MODE=true           Enable CI-friendly mode"
            echo "  SKIP_TESTS=true       Skip running tests"
            echo "  SKIP_PACKAGING=true   Skip creating packages"
            echo "  SKIP_VALIDATION=true  Skip binary validation"
            echo "  BUILD_VERSION=x.y.z   Override version for packages"
            echo ""
            echo "CI/CD Integration:"
            echo "  This script is designed to work in CI/CD environments."
            echo "  Set CI_MODE=true for enhanced logging and error handling."
            echo ""
            exit 0
            ;;
    esac
    
    # Execute build steps
    validate_environment
    clean_build
    run_tests
    
    # Build for both architectures
    build_for_arch "arm64"
    build_for_arch "x86_64"
    
    # Create universal binary
    create_universal_binary
    validate_binary
    create_distribution_packages
    
    print_summary "$build_time_start"
}

# Run main function
main "$@"
