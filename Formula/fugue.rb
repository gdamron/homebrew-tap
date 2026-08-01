# typed: false
# frozen_string_literal: true

# Fugue — a platform for creating interactive and generative music.
#
# This formula installs the prebuilt "install unit" published on the public
# gdamron/fugue GitHub release: a single archive holding both the `fugue` CLI
# (which includes `fugue serve`) and the `fugue-mcp` adapter. The macOS binaries
# are code-signed with a Developer ID and notarized, so they clear Gatekeeper
# with no "unidentified developer" wall. No Rust toolchain required.
class Fugue < Formula
  desc "Interactive and generative music runtime — CLI, serve, and MCP adapter"
  homepage "https://github.com/gdamron/fugue"
  version "2026.7.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/gdamron/fugue/releases/download/v#{version}/fugue-tools-aarch64-apple-darwin.tar.gz"
      sha256 "25e1774b024f7e0af8cd4a19c4d78aa836eb1bec026e5dd177cfab8c06b9a710"
    end
    # Intel Macs are not yet a supported prebuilt target (mirrors install.sh).
  end

  on_linux do
    on_arm do
      url "https://github.com/gdamron/fugue/releases/download/v#{version}/fugue-tools-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "6ada77971498a4e757b92fe98d4a66aae6cdba32501ae8e4778b1262ad4693ef"
    end
    on_intel do
      url "https://github.com/gdamron/fugue/releases/download/v#{version}/fugue-tools-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "6c78df6f89ad6e828d50404c88a3205abab5c0cb3922f8ed81f72cf23ca6b2ef"
    end

    # The Linux binaries link ALSA at runtime for audio output.
    depends_on "alsa-lib"
  end

  def install
    # Both executables sit flat at the archive root; co-locating them in the
    # same bin lets `fugue-mcp` find its sibling `fugue serve` daemon.
    bin.install "fugue", "fugue-mcp"
  end

  def caveats
    <<~EOS
      Fugue installed two executables:
        fugue      the CLI, including `fugue serve` (ready to use now)
        fugue-mcp  the MCP adapter for agent hosts

      The CLI works immediately — no further setup needed.

      To register the MCP server with your agent host (Claude Code, Claude
      Desktop, Cursor), run:
        fugue setup

      Preview exactly what it would change, without writing anything:
        fugue setup --print
    EOS
  end

  test do
    # `fugue --help` exercises the CLI with no side effects and lists its
    # subcommands (including `setup`). The CLI has no `--version` flag.
    assert_match "Command-line host for the Fugue runtime", shell_output("#{bin}/fugue --help")
    # fugue-mcp is a long-running stdio MCP server with no --help/--version
    # short-circuit — running it would block — so assert it was installed
    # alongside the CLI rather than executing it.
    assert_predicate bin/"fugue-mcp", :executable?
  end
end
