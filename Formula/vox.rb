class Vox < Formula
  desc "Fast, private, and accurate MP4 audio transcription using native macOS frameworks"
  homepage "https://github.com/jsonify/vox"
  url "https://github.com/jsonify/vox/releases/download/v#{version}/vox-#{version}-macos-universal.tar.gz"
  sha256 "PLACEHOLDER_SHA256_HASH"
  license "MIT"
  version "1.0.0"

  # System requirements
  depends_on :macos => :monterey
  
  # Build dependencies (only needed if building from source)
  depends_on :xcode => ["14.0", :build] if build.from_source?
  
  # No runtime dependencies - self-contained binary using native frameworks

  def install
    bin.install "vox"
    
    # Install man page if available
    if File.exist?("docs/vox.1")
      man1.install "docs/vox.1"
    end
    
    # Install shell completions if available
    if Dir.exist?("completions")
      bash_completion.install "completions/vox.bash" => "vox" if File.exist?("completions/vox.bash")
      zsh_completion.install "completions/_vox" if File.exist?("completions/_vox")
      fish_completion.install "completions/vox.fish" if File.exist?("completions/vox.fish")
    end
  end

  test do
    # Basic functionality test
    assert_match "vox", shell_output("#{bin}/vox --help")
    assert_match version.to_s, shell_output("#{bin}/vox --version")
    
    # Test with invalid file to ensure error handling
    assert_match "Error", shell_output("#{bin}/vox nonexistent.mp4 2>&1", 1)
  end
end