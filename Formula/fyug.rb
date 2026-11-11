# typed: false
# frozen_string_literal: true

# Fyug — a platform for creating interactive and generative music.
#
# This formula installs the prebuilt "install unit" published on the public
# Ilusiv-media/fyug GitHub release: a single archive holding the `fyug` CLI
# (which includes `fyug serve`) and the `fyug-mcp` adapter, plus the
# `fyug-setup` app on macOS. The macOS binaries are code-signed with a
# Developer ID and notarized, so they clear Gatekeeper with no "unidentified
# developer" wall. No Rust toolchain required.
class Fyug < Formula
  desc "Interactive and generative music runtime — CLI, serve, and MCP adapter"
  homepage "https://github.com/Ilusiv-media/fyug"
  version "2026.11.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/Ilusiv-media/fyug/releases/download/v#{version}/fyug-tools-aarch64-apple-darwin.tar.gz"
      sha256 "8d06c1ce4aa68dba1a877911062fa28beeb606043ab0ae6d84202f07cfdfc216"
    end
    # Releases publish no Intel Mac build.
  end

  on_linux do
    on_arm do
      url "https://github.com/Ilusiv-media/fyug/releases/download/v#{version}/fyug-tools-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "3fdff1ba8fd92098a2a9272f4f04db168935bac593a2b2951ab2f9ad1d18a5c9"
    end
    on_intel do
      url "https://github.com/Ilusiv-media/fyug/releases/download/v#{version}/fyug-tools-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "d77490a6da569d90affd288c91f01da1c2abdfbf5d00bb2117669e2d6dd4ea16"
    end

    # The Linux binaries link ALSA at runtime for audio output.
    depends_on "alsa-lib"
  end

  def install
    # The executables sit flat at the archive root; co-locating them in the
    # same bin lets `fyug-mcp` find its sibling `fyug serve` daemon.
    bin.install "fyug", "fyug-mcp"
    # The setup app ships in the macOS archive only.
    bin.install "fyug-setup" if File.exist?("fyug-setup")

    # The license notices of every crate in those binaries, which their MIT,
    # Apache-2.0 and other licenses require to ship with them.
    doc.install "THIRD_PARTY_LICENSES.txt"
  end

  def post_install
    # A daemon left running from a previous version keeps the OLD build resident
    # in memory. `fyug-mcp` refuses to drive a daemon whose build hash differs
    # from its own, so after an upgrade every MCP connection fails until that
    # stale daemon is stopped. Ask it to shut down cleanly now (it persists its
    # live session first); the next `fyug connect` or MCP client spawns a fresh
    # daemon on this build. Best-effort — `fyug shutdown` exits 0 whether or
    # not a daemon is running, and quiet_system ignores a non-zero exit.
    ohai "Stopping any running Fugue daemon so it restarts on the new build"
    quiet_system bin/"fyug", "shutdown"
  end

  def caveats
    <<~EOS
      Fyug installed these executables:
        fyug       the CLI, including `fyug serve` (ready to use now)
        fyug-mcp   the MCP adapter for agent hosts
        fyug-setup the setup app (macOS only)

      The CLI works immediately — no further setup needed.

      To register the MCP server with your agent host (Claude Code, Claude
      Desktop, Cursor), run:
        fyug setup

      Preview exactly what it would change, without writing anything:
        fyug setup --print

      Upgrading from the `fugue` formula? Its `fugue` and `fugue-mcp`
      executables are gone, so run `fyug setup` once to point your agent
      hosts at `fyug-mcp`.
    EOS
  end

  test do
    # `fyug --help` exercises the CLI with no side effects and lists its
    # subcommands (including `setup`). The CLI has no `--version` flag.
    assert_match "Command-line host for the Fugue runtime", shell_output("#{bin}/fyug --help")
    # fyug-mcp is a long-running stdio MCP server with no --help/--version
    # short-circuit — running it would block — so assert it was installed
    # alongside the CLI rather than executing it.
    assert_predicate bin/"fyug-mcp", :executable?
  end
end
