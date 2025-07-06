#!/bin/bash

# Pre-commit hook for performance testing and code quality checks
# This script helps prevent common issues that cause CI failures

set -e

echo "🔍 Running pre-commit performance and quality checks..."

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "Package.swift" ]; then
    echo -e "${RED}❌ Error: Must be run from the project root directory${NC}"
    exit 1
fi

# Function to print status
print_status() {
    echo -e "${BLUE}→${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

# 1. Check for fatalError in test files
print_status "Checking for fatalError usage in test files..."
if grep -r "fatalError(" Tests/ --include="*.swift" > /dev/null 2>&1; then
    print_error "Found fatalError usage in test files:"
    grep -rn "fatalError(" Tests/ --include="*.swift" | head -5
    echo -e "${RED}This will cause CI test failures. Please replace with proper error handling.${NC}"
    exit 1
else
    print_success "No fatalError usage found in test files"
fi

# 2. Check for extremely long lines (>180 characters)
print_status "Checking for long lines that will fail SwiftLint..."
long_lines_found=false

while IFS= read -r -d '' file; do
    if [ -f "$file" ]; then
        line_num=1
        while IFS= read -r line; do
            if [ ${#line} -gt 180 ]; then
                if [ "$long_lines_found" = false ]; then
                    print_error "Found lines longer than 180 characters:"
                    long_lines_found=true
                fi
                echo -e "${RED}  $file:$line_num (${#line} chars)${NC}"
                echo "    ${line:0:100}..."
            fi
            ((line_num++))
        done < "$file"
    fi
done < <(find Sources Tests -name "*.swift" -print0)

if [ "$long_lines_found" = true ]; then
    echo -e "${RED}Please break long lines to avoid SwiftLint failures in CI.${NC}"
    exit 1
else
    print_success "No excessively long lines found"
fi

# 3. Check for common performance test issues
print_status "Checking for common performance test issues..."

# Check for missing XCTestExpectation fulfillment in async tests
if grep -r "XCTestExpectation" Tests/ --include="*.swift" | grep -v "fulfill" > /dev/null 2>&1; then
    print_warning "Found XCTestExpectation without obvious fulfillment - ensure all expectations are fulfilled"
fi

# Check for force unwrapping in new files
staged_files=$(git diff --cached --name-only --diff-filter=A | grep "\.swift$" || true)
if [ -n "$staged_files" ]; then
    for file in $staged_files; do
        if grep -n "!" "$file" | grep -E "!\s*$" > /dev/null 2>&1; then
            print_warning "Found potential force unwrapping in new file: $file"
            grep -n "!" "$file" | grep -E "!\s*$" | head -3
        fi
    done
fi

# 4. Quick build check
print_status "Running quick build check..."
if swift build > /dev/null 2>&1; then
    print_success "Project builds successfully"
else
    print_error "Project build failed - fix compilation errors before committing"
    swift build
    exit 1
fi

# 5. Run critical tests to catch obvious failures
print_status "Running critical tests to prevent CI failures..."
if swift test --filter CITests > /dev/null 2>&1; then
    print_success "Critical CI tests pass"
else
    print_error "Critical CI tests failed - this will fail in CI"
    echo "Run: swift test --filter CITests"
    exit 1
fi

# 6. Check SwiftLint on staged files only
print_status "Running SwiftLint on staged files..."
staged_swift_files=$(git diff --cached --name-only | grep "\.swift$" || true)
if [ -n "$staged_swift_files" ]; then
    # Create temporary file with just staged changes
    temp_dir=$(mktemp -d)
    lint_failed=false
    
    for file in $staged_swift_files; do
        if [ -f "$file" ]; then
            # Copy the staged version to temp directory
            mkdir -p "$temp_dir/$(dirname "$file")"
            git show :"$file" > "$temp_dir/$file" 2>/dev/null || cp "$file" "$temp_dir/$file"
            
            # Run SwiftLint on the file
            if ! swiftlint lint "$temp_dir/$file" --quiet; then
                lint_failed=true
            fi
        fi
    done
    
    rm -rf "$temp_dir"
    
    if [ "$lint_failed" = true ]; then
        print_error "SwiftLint violations found in staged files"
        echo -e "${BLUE}Run 'swiftlint --fix' to auto-fix some issues${NC}"
        exit 1
    else
        print_success "SwiftLint checks passed for staged files"
    fi
else
    print_success "No Swift files staged for commit"
fi

# 7. Check for performance test specific issues
print_status "Checking performance test specific patterns..."

# Check for proper timeout values in performance tests
if find Tests -name "*Performance*.swift" -exec grep -l "timeout:" {} \; | xargs grep "timeout:" | grep -E "timeout:\s*[0-9]+\." > /dev/null 2>&1; then
    timeout_issues=$(find Tests -name "*Performance*.swift" -exec grep -l "timeout:" {} \; | xargs grep -n "timeout:" | grep -E "timeout:\s*[1-5]\.")
    if [ -n "$timeout_issues" ]; then
        print_warning "Found potentially short timeout values in performance tests:"
        echo "$timeout_issues"
        echo -e "${YELLOW}Consider using longer timeouts (>30s) for performance tests${NC}"
    fi
fi

# Check for proper memory management in tests
if grep -r "UnsafeMutablePointer" Tests/ --include="*.swift" | grep -v "defer.*deallocate" > /dev/null 2>&1; then
    print_warning "Found UnsafeMutablePointer without obvious deallocation - check for memory leaks"
fi

print_success "All pre-commit checks passed!"
echo -e "${GREEN}✨ Ready to commit!${NC}"