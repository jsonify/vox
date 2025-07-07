# Homebrew Distribution

This document outlines the Homebrew tap configuration for Vox CLI distribution.

## Tap Repository Structure

The Homebrew tap will be hosted at: `https://github.com/jsonify/homebrew-vox`

```
homebrew-vox/
├── Formula/
│   └── vox.rb          # Main formula file
├── README.md           # Installation instructions
├── LICENSE             # MIT License
└── .github/
    └── workflows/
        └── update-formula.yml  # Automated formula updates
```

## Installation Methods

### Via Tap
```bash
# Add tap and install
brew tap jsonify/vox
brew install vox

# Or in one command
brew install jsonify/vox/vox
```

### Direct Formula URL
```bash
brew install https://raw.githubusercontent.com/jsonify/homebrew-vox/main/Formula/vox.rb
```

## Formula Configuration

### Distribution Strategy
- **Pre-built Universal Binary**: Recommended approach
- **Supported Architectures**: ARM64 + x86_64 (universal binary)
- **Minimum macOS**: 12.0 (Monterey)
- **Package Format**: `.tar.gz` with SHA256 checksum

### Dependencies
- **Runtime**: None (self-contained binary)
- **Build** (if from source): Xcode 14.0+, Swift 5.9+

### Assets Included
- Binary: `vox` executable
- Documentation: `docs/vox.1` man page
- Shell Completions: Bash, Zsh, Fish (if available)

## Version Management

### Automated Updates
The formula will be automatically updated via GitHub Actions when new releases are published:

1. Release workflow generates universal binary
2. Calculate SHA256 checksum
3. Update formula with new version and hash
4. Commit and push to tap repository

### Manual Updates
For manual formula updates:
```bash
brew bump-formula-pr jsonify/vox --url=RELEASE_URL --sha256=CHECKSUM
```

## Testing

### Formula Testing
```bash
# Test formula syntax
brew audit --strict vox.rb

# Test installation
brew install --build-from-source vox
brew test vox

# Test upgrade
brew upgrade vox
```

### CI/CD Integration
- Automated testing on macOS versions
- Formula validation and linting
- Installation verification

## Distribution Benefits

### For Users
- Simple installation: `brew install jsonify/vox`
- Automatic updates: `brew upgrade vox`
- Universal binary support (Intel + Apple Silicon)
- No build dependencies required

### For Developers
- Automated release process
- Version synchronization
- Built-in testing framework
- Professional distribution channel

## Release Integration

The Homebrew formula integrates with the existing release workflow:

1. **Build Phase**: Universal binary created by `build.sh`
2. **Package Phase**: Distribution archives with checksums
3. **Release Phase**: GitHub release with assets
4. **Update Phase**: Automated formula update
5. **Distribution Phase**: Available via Homebrew

## Maintenance

### Regular Tasks
- Monitor formula updates
- Test on new macOS versions
- Update dependencies if needed
- Verify universal binary compatibility

### Troubleshooting
- Check formula syntax with `brew audit`
- Verify checksums match release assets
- Test installation on clean systems
- Monitor user feedback and issues

## Security Considerations

### Binary Verification
- SHA256 checksums for all releases
- Signed releases from trusted source
- Universal binary validation

### Distribution Security
- Public tap repository for transparency
- Automated updates reduce manual errors
- Built-in Homebrew security features

## Future Enhancements

### Planned Features
- Shell completion installation
- Man page distribution
- Plugin system support (if applicable)
- Performance optimizations

### Monitoring
- Installation analytics via Homebrew
- User feedback collection
- Performance metrics tracking
- Error reporting integration

This Homebrew distribution strategy provides professional-grade package management while maintaining the security and performance standards established in the Vox CLI project.