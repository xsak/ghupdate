# ghupdate

Check for and install updates of CLI tools that are downloaded from
GitHub Releases and placed in a directory on your `PATH`
(e.g. `lazygit`, `lazydocker`, `helm`, `lfk`).

Single-file Python 3.9+ script, standard library only, no dependencies. Linux.

## Install

```sh
make install
```

installs the script to `~/.local/bin` (override with `DEST=...`) and seeds
`~/.config/ghupdate/config.json` from the example — only if no config
exists yet. `make uninstall` removes the binary, keeping config and state.

Or manually:

```sh
cp ghupdate ~/.local/bin/
chmod +x ~/.local/bin/ghupdate
mkdir -p ~/.config/ghupdate
cp config.example.json ~/.config/ghupdate/config.json
```

## Usage

```
ghupdate                     # check all tools (default action)
ghupdate check lazygit helm  # check specific tools
ghupdate update              # update all tools
ghupdate update lfk          # update one tool
```

`check` never downloads anything — it queries the GitHub API, compares the
latest release against the installed version, and validates that the
configured asset template matches the release.

`update` downloads the release to a temp directory, extracts the binary, and
moves it into `bin_dir`. The previous binary is kept as `<tool>.old`
(replace on each update). If the install fails for any reason, the old
binary is restored.

Example output:

```
lazygit  update           0.44.0 -> 0.65.1
helm     up to date       4.3.0
lfk      not installed    latest 0.19.2
```

## Configuration

`~/.config/ghupdate/config.json` (override the path with `--config` or
`GHUPDATE_CONFIG`). See `config.example.json`.

| key                  | meaning |
|----------------------|---------|
| `bin_dir`            | directory the binaries are installed to (default `~/.local/bin`) |
| `arch`               | value substituted for `{arch}` (default: `uname -m`, e.g. `x86_64`) |
| `tools.<name>.repo`  | GitHub repo, `owner/name` |
| `tools.<name>.asset` | release-asset name template (see placeholders below) |
| `tools.<name>.url`   | alternative to `asset`: direct download URL template, for repos that don't host binaries in the release (e.g. helm uses `get.helm.sh`) |
| `tools.<name>.extract` | path of the binary inside the archive; omit if the asset is a raw binary |
| `tools.<name>.arch`  | per-tool override for `{arch}` |
| `tools.<name>.version_cmd` | override how the installed version is probed (e.g. `--version --short` or `version`); default: try `--version`, then `version` |

Placeholders in `asset` and `url` templates:

- `{version}` — release tag with a leading `v` stripped (tag `v0.65.1` → `0.65.1`)
- `{arch}` — the `arch` value (global or per-tool)

Architecture: repos disagree about arch naming (`x86_64` vs `amd64`,
`aarch64` vs `arm64`, ...), so the machine arch and its aliases are tried
in order (`x86_64` → `amd64`, `aarch64` → `arm64`, `i686` → `386`, plus
`armv6l`/`armv7l` → `armv6`/`armv7`/`arm`). For `asset` tools the names are
matched against the release's asset list; for `url` tools each candidate
URL is tried and a 404 moves on to the next alias. The arch of the URL that
actually downloads is also the one used to render `extract`, so archive
layouts like `linux-amd64/helm` work without any per-tool `arch`.

The example config is therefore arch-agnostic: it works as-is on x86-64
boxes and on 64-bit ARM (e.g. Raspberry Pi 3/4/5 with a 64-bit OS). If a
repo uses unusual naming (or you're on 32-bit ARM), pin it with the
per-tool `arch` key.

## Adding a tool

1. Open the repo's Releases page and find the asset for your platform
   (e.g. `lazygit_0.65.1_linux_x86_64.tar.gz`).
2. Copy the pattern into an `asset` template, replacing the version with
   `{version}` and the architecture with `{arch}`.
3. Download/extract the asset once to see what the binary is called inside
   the archive — that goes into `extract` (it may be nested, e.g.
   `linux-amd64/helm`).

## Development

```sh
make check                  # offline: python syntax + example config validity
make test                   # end-to-end: install all example tools into a temp dir
make test TOOLS=lazydocker  # a subset
```

`make test` hits the network: it downloads each tool's latest release,
installs it into a temporary directory, and runs the binary.

## Version tracking

Installed versions are recorded in the state file
`~/.local/state/ghupdate/state.json` (override with `--state` or
`GHUPDATE_STATE`) after each successful update. If there's no state entry
yet, `ghupdate` probes the installed binary for its version: it tries
the per-tool `version_cmd` (default: `--version`, then the `version`
subcommand, since e.g. helm doesn't support `--version`).

## Notes

- Uses the unauthenticated GitHub API (60 requests/hour); set `GITHUB_TOKEN`
  for a higher limit (5000/hour).
- Only non-prerelease releases are considered.
- Downloads are capped at 512 MiB; archives are extracted into a private temp
  directory with path-traversal and special-file checks (absolute or `..`
  paths and symlink/hardlink/device members are rejected), so a malicious
  asset can't write outside the temp directory.
- Checksums are not verified. The binaries come from the repos' official
  GitHub release assets, but if that's a concern, prefer tools whose release
  provides signatures and verify manually.
