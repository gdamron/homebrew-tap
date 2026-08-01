# gdamron/homebrew-tap

Homebrew formulae for [Fugue](https://github.com/gdamron/fugue) — a platform for
creating interactive and generative music.

## Install

```sh
brew install gdamron/tap/fugue
```

This installs two executables:

- **`fugue`** — the command-line host, including `fugue serve` (the local
  runtime daemon). Ready to use immediately.
- **`fugue-mcp`** — the MCP adapter that lets agent hosts drive Fugue.

The macOS binaries are code-signed with a Developer ID and notarized, so they
clear Gatekeeper with no "unidentified developer" prompt. No Rust toolchain is
required.

### Register the MCP server

The CLI works on its own. To register the MCP server with your agent host
(Claude Code, Claude Desktop, Cursor):

```sh
fugue setup          # detect hosts and write the registration
fugue setup --print  # preview the changes without writing
```

## Supported platforms

| Platform            | Prebuilt |
| ------------------- | -------- |
| macOS (Apple Silicon) | ✅     |
| Linux (x86_64)      | ✅       |
| Linux (arm64)       | ✅       |
| macOS (Intel)       | —        |
| Windows             | use the installer / WSL |

Intel Macs and native Windows are not yet published as Homebrew-installable
prebuilts; see the [installer](https://github.com/gdamron/fugue#install) for
those.
