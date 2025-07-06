#!/bin/bash

# Quick CI validation script
# Checks critical items that commonly cause CI failures

set -e  # Exit on any error

echo "🔍 Quick CI Validation..."

# Test 1: Build check
echo "1. Testing build..."
if swift build > /dev/null 2>&1; then
    echo "✅ Build successful"
else
    echo "❌ Build failed"
    echo "Run 'swift build' to see the error details"
    exit 1
fi

# Test 2: SwiftLint critical errors
echo "2. Checking SwiftLint errors..."
if command -v swiftlint > /dev/null 2>&1; then
    ERROR_COUNT=$(swiftlint lint --quiet | grep "::error" | wc -l | tr -d ' ')
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo "❌ Found $ERROR_COUNT SwiftLint errors"
        echo "Run '.git/hooks/pre-commit' to see details"
        exit 1
    else
        echo "✅ No SwiftLint errors"
    fi
else
    echo "⚠️ SwiftLint not installed - skipping check"
fi

# Test 3: CI Tests
echo "3. Testing CI tests..."
if swift test --filter CITests > /dev/null 2>&1; then
    echo "✅ CI tests pass"
else
    echo "❌ CI tests failed"
    echo "Run 'swift test --filter CITests' to see the error details"
    exit 1
fi

echo ""
echo "🎉 All checks passed! CI should succeed."
echo ""
echo "Usage tips:"
echo "  • Run this script before pushing: ./validate_ci.sh"
echo "  • Add to your workflow: git add . && ./validate_ci.sh && git commit -m 'message'"
echo "  • For detailed checks: .git/hooks/pre-commit"