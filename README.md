# gdamron/homebrew-tap

Homebrew formulae for [Fyug](https://github.com/Ilusiv-media/fyug), a platform
for creating interactive and generative music.

## Install

```sh
brew install gdamron/tap/fyug
```

This installs these executables:

- **`fyug`** — the command-line host, including `fyug serve` (the local
  runtime daemon). Ready to use immediately.
- **`fyug-mcp`** — the MCP adapter that lets agent hosts drive Fyug.
- **`fyug-setup`** — the setup app, on macOS only.

The macOS binaries are code-signed with a Developer ID and notarized, so they
clear Gatekeeper with no "unidentified developer" prompt. No Rust toolchain is
required.

The license notices of the third-party code in those binaries are installed at
`$(brew --prefix)/share/doc/fyug/THIRD_PARTY_LICENSES.txt`.

### Register the MCP server

The CLI works on its own. To register the MCP server with your agent host
(Claude Code, Claude Desktop, Cursor):

```sh
fyug setup          # detect hosts and write the registration
fyug setup --print  # preview the changes without writing
```

### Upgrading from `fugue`

The formula was called `fugue` before 2026.11.0. `brew upgrade` moves an
existing `fugue` install to `fyug`. The `fugue` and `fugue-mcp` executables are
replaced by `fyug` and `fyug-mcp`, so run `fyug setup` once to point your agent
hosts at the new adapter.

## Supported platforms

| Platform              | Prebuilt |
| --------------------- | -------- |
| macOS (Apple Silicon) | ✅       |
| Linux (x86_64)        | ✅       |
| Linux (arm64)         | ✅       |
| macOS (Intel)         | —        |
| Windows               | use the installer |

Intel Macs have no prebuilt release. For native Windows, use the
[installer](https://github.com/Ilusiv-media/fyug#install).
