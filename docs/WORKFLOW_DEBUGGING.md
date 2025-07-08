# Workflow Debugging Guide

## Overview

This document outlines the debugging process and fixes applied to the Homebrew formula update workflows for the Vox project.

## Issues Identified

### 1. Workflow Trigger Problem
- **Issue**: The `update-homebrew-formula.yml` workflow was not triggering after releases
- **Root Cause**: `softprops/action-gh-release@v2` doesn't consistently trigger the `release.published` event
- **Evidence**: No workflow runs visible for the `update-homebrew-formula.yml` after v1.1.3 release

### 2. Secret Dependency
- **Issue**: Workflow relied on `HOMEBREW_UPDATE_TOKEN` secret that may not be configured
- **Root Cause**: Custom token requirement created a dependency that could fail silently
- **Evidence**: Unable to list secrets via CLI (security restriction)

### 3. Asset Validation
- **Issue**: Suspected empty release assets based on SHA256 calculation problems
- **Root Cause**: This was a false positive - assets were actually valid
- **Evidence**: v1.1.3 release assets verified as properly created (806KB tar.gz)

## Solutions Implemented

### 1. Integrated Homebrew Update in Release Workflow
```yaml
- name: Update Homebrew Formula
  if: "!contains(steps.version.outputs.version, '-')"
  run: |
    # Calculate SHA256 for Homebrew formula
    cd dist
    ASSET_NAME="vox-${{ steps.version.outputs.version }}-macos-universal.tar.gz"
    SHA256=$(shasum -a 256 "$ASSET_NAME" | cut -d' ' -f1)
    
    # Clone homebrew-vox repository
    cd ..
    git clone https://github.com/jsonify/homebrew-vox.git homebrew-vox
    cd homebrew-vox
    
    # Create branch and update formula
    BRANCH_NAME="update-v${{ steps.version.outputs.version }}"
    git checkout -b "$BRANCH_NAME"
    
    # Update formula
    sed -i.bak "s/version \".*\"/version \"${{ steps.version.outputs.version }}\"/" Formula/vox.rb
    sed -i.bak "s/sha256 \".*\"/sha256 \"$SHA256\"/" Formula/vox.rb
    
    # Commit and push
    git add Formula/vox.rb
    git commit -m "Update vox to v${{ steps.version.outputs.version }}"
    git push origin "$BRANCH_NAME"
    
    # Create PR
    gh pr create --title "Update vox to v${{ steps.version.outputs.version }}" --body "..." --base main --head "$BRANCH_NAME"
```

**Benefits:**
- Eliminates trigger dependency issues
- Uses standard `GITHUB_TOKEN` instead of custom secret
- Runs immediately after successful release creation
- Creates branch-based updates with PR review process

### 2. Enhanced Fallback Workflow
```yaml
name: Update Homebrew Formula (Fallback)

on:
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to update (e.g., 1.1.3)'
        required: true
        type: string
```

**Improvements:**
- Added manual trigger capability
- Enhanced error handling and validation
- Better asset verification
- Comprehensive logging
- Fallback PR creation on failure

### 3. Error Handling Enhancements
- **Asset Validation**: Verify file existence and size before processing
- **Repository Access**: Graceful handling of missing homebrew repository
- **SHA256 Calculation**: Validate hash generation before use
- **Branch Management**: Safe branch creation and push operations
- **PR Creation**: Fallback handling for PR creation failures

## Testing Process

### Test Release Creation
```bash
# Create test branch
git checkout -b fix/homebrew-workflow-debugging

# Make changes and commit
git add .github/workflows/
git commit -m "fix: debug and enhance homebrew formula update workflows"

# Push branch
git push origin fix/homebrew-workflow-debugging

# Create test tag
git tag v1.1.4-test
git push origin v1.1.4-test
```

### Workflow Validation
1. **Release Workflow**: Triggers on tag push, builds assets, creates release
2. **Homebrew Update**: Integrated step that creates PR for formula updates
3. **Fallback Workflow**: Available for manual triggers if needed

## Key Fixes Applied

### 1. YAML Syntax Issues
```yaml
# Before (incorrect)
if: ${{ !contains(steps.version.outputs.version, '-') }}

# After (correct)
if: "!contains(steps.version.outputs.version, '-')"
```

### 2. Environment Variables
```yaml
env:
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}  # Added for gh CLI
```

### 3. Branch-Based Updates
- Changed from direct `main` branch pushes to feature branches
- Added PR creation for review process
- Better collaboration and safety

## Future Improvements

### 1. Homebrew Repository Setup
- Consider creating the `homebrew-vox` repository if it doesn't exist
- Add proper formula template and structure

### 2. Enhanced Validation
- Add formula syntax validation before committing
- Test formula installation in CI environment
- Validate download URLs and checksums

### 3. Monitoring
- Add workflow status notifications
- Create dashboard for release and formula update status
- Alert on consecutive failures

## Troubleshooting

### Common Issues
1. **Repository Not Found**: Verify `homebrew-vox` repository exists and is accessible
2. **Permission Denied**: Check if `GITHUB_TOKEN` has proper permissions
3. **SHA256 Mismatch**: Verify asset integrity and download process
4. **Workflow Syntax**: Validate YAML syntax using online tools

### Manual Recovery
```bash
# Manual trigger of fallback workflow
gh workflow run update-homebrew-formula.yml -f version=1.1.3

# Check workflow status
gh run list --workflow=update-homebrew-formula.yml

# View logs
gh run view [run-id] --log
```

## References
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Homebrew Formula Documentation](https://docs.brew.sh/Formula-Cookbook)
- [softprops/action-gh-release](https://github.com/softprops/action-gh-release)