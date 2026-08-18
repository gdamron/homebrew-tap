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
  version "2026.8.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/gdamron/fugue/releases/download/v#{version}/fugue-tools-aarch64-apple-darwin.tar.gz"
      sha256 "d041671c075df366635de98fbe3d804a9f801f852388d633ab42766073014fe5"
    end
    # Intel Macs are not yet a supported prebuilt target (mirrors install.sh).
  end

  on_linux do
    on_arm do
      url "https://github.com/gdamron/fugue/releases/download/v#{version}/fugue-tools-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "45dea7395fc10c24480e0d9e02dd7145ad5d8105a40a437827ade264c296bac5"
    end
    on_intel do
      url "https://github.com/gdamron/fugue/releases/download/v#{version}/fugue-tools-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "857f39438475b5647ea78bdfa681a33db4faf87995515f702b7a632a4f5c5a16"
    end

    # The Linux binaries link ALSA at runtime for audio output.
    depends_on "alsa-lib"
  end

  def install
    # Both executables sit flat at the archive root; co-locating them in the
    # same bin lets `fugue-mcp` find its sibling `fugue serve` daemon.
    bin.install "fugue", "fugue-mcp"
  end

  def post_install
    # A daemon left running from a previous version keeps the OLD build resident
    # in memory. `fugue-mcp` refuses to drive a daemon whose build hash differs
    # from its own, so after an upgrade every MCP connection fails until that
    # stale daemon is stopped. Ask it to shut down cleanly now (it persists its
    # live session first); the next `fugue connect` or MCP client spawns a fresh
    # daemon on this build. Best-effort and safe to run unconditionally —
    # `fugue shutdown` exits 0 whether or not a daemon is running, and
    # quiet_system never fails the install if a wedged daemon returns non-zero.
    ohai "Stopping any running fugue daemon so it restarts on the new build"
    quiet_system bin/"fugue", "shutdown"
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
