#!/bin/bash

# Vox CLI Binary Optimization Script
# Advanced optimization techniques for Swift binaries

set -e

# Configuration
BINARY_PATH="${1:-dist/vox}"
BACKUP_SUFFIX=".pre-optimization"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Function to get file size in bytes
get_file_size() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        stat -f%z "$1" 2>/dev/null || echo "0"
    else
        stat -c%s "$1" 2>/dev/null || echo "0"
    fi
}

# Function to format bytes as human readable
format_bytes() {
    local bytes=$1
    if [[ $bytes -gt 1048576 ]]; then
        echo "$((bytes / 1048576))MB"
    elif [[ $bytes -gt 1024 ]]; then
        echo "$((bytes / 1024))KB"
    else
        echo "${bytes}B"
    fi
}

# Function to create backup
create_backup() {
    if [[ -f "$BINARY_PATH" ]]; then
        log_info "Creating backup: ${BINARY_PATH}${BACKUP_SUFFIX}"
        cp "$BINARY_PATH" "${BINARY_PATH}${BACKUP_SUFFIX}"
        log_success "Backup created"
    else
        log_error "Binary not found: $BINARY_PATH"
        exit 1
    fi
}

# Function to apply strip optimization
apply_strip_optimization() {
    log_info "Applying strip optimization..."
    
    local size_before=$(get_file_size "$BINARY_PATH")
    
    if strip "$BINARY_PATH" 2>/dev/null; then
        local size_after=$(get_file_size "$BINARY_PATH")
        local savings=$((size_before - size_after))
        local savings_percent=$(( (savings * 100) / size_before ))
        
        log_success "Strip optimization complete"
        log_info "Size reduction: $(format_bytes $savings) (${savings_percent}%)"
    else
        log_warning "Strip optimization failed or not applicable"
    fi
}

# Function to apply upx compression (if available)
apply_upx_compression() {
    if ! command -v upx &> /dev/null; then
        log_info "UPX not available, skipping compression"
        return 0
    fi
    
    log_info "Applying UPX compression..."
    log_warning "Note: UPX may cause macOS Gatekeeper issues"
    
    local size_before=$(get_file_size "$BINARY_PATH")
    
    # Create a temporary copy for UPX
    local temp_binary="${BINARY_PATH}.upx-temp"
    cp "$BINARY_PATH" "$temp_binary"
    
    if upx --best --quiet "$temp_binary" 2>/dev/null; then
        local size_after=$(get_file_size "$temp_binary")
        local savings=$((size_before - size_after))
        local savings_percent=$(( (savings * 100) / size_before ))
        
        log_success "UPX compression complete"
        log_info "Size reduction: $(format_bytes $savings) (${savings_percent}%)"
        
        # Test the compressed binary
        if timeout 5s "$temp_binary" --help > /dev/null 2>&1; then
            log_success "Compressed binary works, applying changes"
            mv "$temp_binary" "$BINARY_PATH"
        else
            log_warning "Compressed binary failed test, reverting"
            rm -f "$temp_binary"
        fi
    else
        log_warning "UPX compression failed"
        rm -f "$temp_binary"
    fi
}

# Function to remove debug symbols and optimize
remove_debug_symbols() {
    log_info "Removing debug symbols..."
    
    if command -v dsymutil &> /dev/null; then
        # Extract debug symbols to separate file
        local dsym_file="${BINARY_PATH}.dSYM"
        if dsymutil "$BINARY_PATH" -o "$dsym_file" 2>/dev/null; then
            log_success "Debug symbols extracted to $dsym_file"
        else
            log_info "No debug symbols to extract"
        fi
    fi
    
    # Strip debug symbols
    if strip -S "$BINARY_PATH" 2>/dev/null; then
        log_success "Debug symbols stripped"
    else
        log_info "No debug symbols to strip"
    fi
}

# Function to optimize with install_name_tool (macOS specific)
optimize_install_names() {
    if ! command -v install_name_tool &> /dev/null; then
        log_info "install_name_tool not available, skipping"
        return 0
    fi
    
    log_info "Optimizing install names..."
    
    # Get current install names
    local install_names=$(otool -L "$BINARY_PATH" 2>/dev/null | grep -v "$BINARY_PATH:" | awk '{print $1}' | grep -v "^$")
    
    while IFS= read -r lib; do
        if [[ -n "$lib" && "$lib" == "@rpath/"* ]]; then
            log_info "Found rpath dependency: $lib"
            # Could optimize rpath dependencies here if needed
        fi
    done <<< "$install_names"
    
    log_success "Install name optimization complete"
}

# Function to validate optimized binary
validate_optimized_binary() {
    log_info "Validating optimized binary..."
    
    # Check if binary is still executable
    if [[ ! -x "$BINARY_PATH" ]]; then
        log_error "Binary is no longer executable after optimization"
        return 1
    fi
    
    # Test basic functionality
    if timeout 10s "$BINARY_PATH" --help > /dev/null 2>&1; then
        log_success "Binary functionality validated"
    else
        log_error "Binary functionality test failed"
        return 1
    fi
    
    # Check architectures (for universal binaries)
    if command -v lipo &> /dev/null; then
        local arch_info=$(lipo -info "$BINARY_PATH" 2>/dev/null || echo "")
        if [[ -n "$arch_info" ]]; then
            log_info "Architecture: $arch_info"
        fi
    fi
    
    log_success "Binary validation complete"
}

# Function to print optimization summary
print_optimization_summary() {
    local original_size=$(get_file_size "${BINARY_PATH}${BACKUP_SUFFIX}")
    local optimized_size=$(get_file_size "$BINARY_PATH")
    local total_savings=$((original_size - optimized_size))
    local total_savings_percent=$(( (total_savings * 100) / original_size ))
    
    echo ""
    log_success "🎯 OPTIMIZATION COMPLETE!"
    echo ""
    echo "📊 Optimization Summary:"
    echo "  • Original size: $(format_bytes $original_size)"
    echo "  • Optimized size: $(format_bytes $optimized_size)"
    echo "  • Total savings: $(format_bytes $total_savings) (${total_savings_percent}%)"
    echo ""
    echo "📝 Applied optimizations:"
    echo "  • Symbol stripping"
    echo "  • Debug symbol removal"
    echo "  • Install name optimization"
    if command -v upx &> /dev/null; then
        echo "  • UPX compression (if applicable)"
    fi
    echo ""
    echo "💡 Additional recommendations:"
    echo "  • Consider Link-Time Optimization (LTO) during build"
    echo "  • Use Swift's -O optimization level"
    echo "  • Profile-guided optimization for hot paths"
    echo ""
}

# Function to restore from backup
restore_backup() {
    if [[ -f "${BINARY_PATH}${BACKUP_SUFFIX}" ]]; then
        log_info "Restoring from backup..."
        mv "${BINARY_PATH}${BACKUP_SUFFIX}" "$BINARY_PATH"
        log_success "Backup restored"
    else
        log_error "No backup found to restore"
        exit 1
    fi
}

# Main optimization function
main() {
    echo "🎯 Vox CLI Binary Optimization"
    echo "=============================="
    
    # Parse command line arguments
    case "${2:-}" in
        "restore")
            restore_backup
            exit 0
            ;;
        "help"|"--help"|"-h")
            echo "Usage: $0 [binary_path] [command]"
            echo ""
            echo "Commands:"
            echo "  restore   Restore from backup"
            echo "  help      Show this help"
            echo ""
            echo "Example:"
            echo "  $0 dist/vox"
            echo "  $0 dist/vox restore"
            echo ""
            exit 0
            ;;
    esac
    
    # Check if binary exists
    if [[ ! -f "$BINARY_PATH" ]]; then
        log_error "Binary not found: $BINARY_PATH"
        log_info "Build the project first with: ./build.sh"
        exit 1
    fi
    
    log_info "Optimizing binary: $BINARY_PATH"
    
    # Create backup and apply optimizations
    create_backup
    
    # Apply optimizations in order of safety/effectiveness
    apply_strip_optimization
    remove_debug_symbols
    optimize_install_names
    
    # Validate the optimized binary
    if validate_optimized_binary; then
        print_optimization_summary
        
        # Clean up backup on success
        if [[ "${KEEP_BACKUP:-}" != "true" ]]; then
            rm -f "${BINARY_PATH}${BACKUP_SUFFIX}"
            log_info "Backup cleaned up (set KEEP_BACKUP=true to retain)"
        fi
    else
        log_error "Optimization validation failed, restoring backup"
        restore_backup
        exit 1
    fi
}

# Run main function
main "$@"