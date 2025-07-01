# Contributing to Vox CLI

## Development Workflow

### Prerequisites
- macOS 12.0+ (Monterey or later)
- Xcode 14.0+ with Swift 5.9+
- Swift Package Manager
- GitHub CLI (`gh`) for workflow testing

### Getting Started
1. Fork and clone the repository
2. Create a feature branch: `git checkout -b feature/your-feature-name`
3. Make your changes following the coding standards
4. Run tests: `swift test`
5. Submit a pull request

## CI/CD Pipeline

### Continuous Integration (CI)
The CI pipeline runs on every push and pull request:

- **Multi-platform testing**: Ubuntu (Linux) and macOS
- **Swift versions**: 5.9
- **Code quality**: SwiftLint static analysis
- **Security scanning**: Trivy vulnerability scanner
- **Build validation**: Release configuration builds
- **Universal binary creation**: Intel + Apple Silicon

### Release Process
Releases are automatically triggered when version tags are pushed:

1. **Tag format**: `v1.2.3` (semantic versioning)
2. **Automated builds**: Universal binaries for macOS
3. **GitHub releases**: Automatic release creation with assets
4. **Distribution**: tar.gz and zip archives with checksums

### Testing Workflows Locally

#### Test CI Pipeline
```bash
# Run tests locally
swift test --verbose

# Run SwiftLint (requires installation)
brew install swiftlint
swiftlint lint

# Build release configuration
swift build -c release
```

#### Test Release Pipeline
```bash
# Create a test tag (use a pre-release version)
git tag v0.1.0-test
git push origin v0.1.0-test

# Watch the release workflow
gh run watch

# Clean up test tag
git tag -d v0.1.0-test
git push origin --delete v0.1.0-test
```

## Code Quality Standards

### SwiftLint Rules
The project uses SwiftLint for code quality. Key rules:
- Line length: 120 characters (warning), 200 (error)
- Function body length: 60 lines (warning), 100 (error)
- Avoid force unwrapping and force casting
- Use proper logging instead of print statements

### Testing Requirements
- Unit tests for all public APIs
- Integration tests for CLI functionality
- Code coverage reports via Codecov
- Tests must pass on both Intel and Apple Silicon

### Commit Guidelines
Follow conventional commits format:
- `feat:` for new features
- `fix:` for bug fixes
- `docs:` for documentation changes
- `test:` for test additions/changes
- `ci:` for CI/CD changes

## Troubleshooting CI/CD

### Common Issues

#### Build Failures
1. **Swift version mismatch**: Ensure Swift 5.9+ compatibility
2. **Missing dependencies**: Check Package.swift and Package.resolved
3. **Architecture issues**: Test both Intel and Apple Silicon builds

#### Test Failures
1. **Platform-specific failures**: Some tests may need platform guards
2. **Timing issues**: Use expectation-based testing for async code
3. **Resource issues**: Ensure test resources are included in package

#### Release Issues
1. **Tag format**: Must follow `v*.*.*` pattern
2. **Binary creation**: Universal binary requires both architectures
3. **Asset uploads**: Check file paths and permissions

### Debugging Workflows
1. **View workflow runs**: `gh run list`
2. **Watch live runs**: `gh run watch`
3. **Download logs**: `gh run download <run-id>`
4. **Re-run failed jobs**: `gh run rerun <run-id>`

## Security

### Vulnerability Scanning
- Trivy scans for known vulnerabilities
- Results uploaded to GitHub Security tab
- Address any high/critical findings promptly

### Secrets Management
- Never commit API keys or secrets
- Use GitHub Secrets for sensitive data
- Rotate tokens regularly

## Performance

### Build Optimization
- Swift build caching enabled
- Dependency caching for faster builds
- Universal binary creation optimized

### Resource Usage
- Workflows designed for efficiency
- Artifact retention limited to 7 days
- Matrix builds for parallel testing

## Getting Help

### Documentation
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Swift Package Manager Guide](https://swift.org/package-manager/)
- [SwiftLint Rules](https://realm.github.io/SwiftLint/rule-directory.html)

### Support
- Open an issue for bugs or feature requests
- Check existing issues before creating new ones
- Provide detailed reproduction steps

## Release Checklist

Before creating a release:
- [ ] All tests pass locally and in CI
- [ ] SwiftLint passes without warnings
- [ ] Version updated in appropriate files
- [ ] CHANGELOG updated with new features/fixes
- [ ] Documentation updated if needed
- [ ] Universal binary builds and runs correctly
- [ ] Create git tag following semantic versioning
- [ ] Push tag to trigger release workflow
- [ ] Verify GitHub release is created correctly
- [ ] Test downloaded binaries on clean system