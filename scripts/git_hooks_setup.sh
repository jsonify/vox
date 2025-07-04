#!/bin/bash

# Setup script for Git hooks
# Run this once to install the pre-commit hook

# Create the pre-commit hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash

# Pre-commit hook to run SwiftLint

echo "Running SwiftLint..."

# Check if SwiftLint is installed
if ! command -v swiftlint &> /dev/null; then
    echo "❌ SwiftLint is not installed. Please install it first:"
    echo "   brew install swiftlint"
    exit 1
fi

# Run SwiftLint on staged Swift files
SWIFT_FILES=$(git diff --cached --name-only --diff-filter=d | grep "\.swift$")

if [ -n "$SWIFT_FILES" ]; then
    echo "Linting Swift files: $SWIFT_FILES"
    
    # Run SwiftLint only on staged files
    echo "$SWIFT_FILES" | xargs swiftlint lint --quiet
    
    if [ $? -ne 0 ]; then
        echo ""
        echo "❌ SwiftLint found issues. Please fix them before committing."
        echo "   You can run 'swiftlint lint' to see all issues"
        echo "   Or run 'swiftlint --fix' to auto-fix some issues"
        exit 1
    fi
    
    echo "✅ SwiftLint passed!"
else
    echo "No Swift files to lint."
fi
EOF

# Make the hook executable
chmod +x .git/hooks/pre-commit

echo "✅ Pre-commit hook installed successfully!"
echo ""
echo "Now SwiftLint will run automatically before each commit."
echo "To bypass the hook (not recommended), use: git commit --no-verify"