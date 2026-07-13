# setup-kapi

GitHub Action for installing the [kapi CLI](https://github.com/neokapi/neokapi) in CI workflows.

Downloads the correct binary for the runner platform, verifies SHA-256 checksums, caches between runs, and optionally installs kapi plugins (such as the bowrain plugin, `kapi-bowrain`) and configures server authentication.

## Usage

### Basic

```yaml
steps:
  - uses: neokapi/setup-kapi@v1
```

The built-in `GITHUB_TOKEN` is used by default for release downloads, so no token input is required.

### Pinned version

```yaml
steps:
  - uses: neokapi/setup-kapi@v1
    with:
      version: "1.1.0"
```

### Run a localization pipeline

```yaml
steps:
  - uses: neokapi/setup-kapi@v1

  - run: kapi run
```

### With the bowrain plugin and server auth

```yaml
steps:
  - uses: neokapi/setup-kapi@v1
    with:
      plugins: kapi-bowrain
      auth-token: ${{ secrets.BOWRAIN_AUTH_TOKEN }}
      server: https://your.bowrain.server

  - run: kapi up
```

`kapi up` is the convergence verb: with the bowrain plugin installed and a `server:` block in the recipe, it pushes, converges on the server, and pulls the produced targets back. To run it and commit the results, pair this with [`kapi-action`](https://github.com/neokapi/kapi-action).

## Inputs

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `version` | Kapi CLI version (e.g. `1.1.0`), or `latest` for the newest stable CLI release | `latest` | No |
| `token` | GitHub token for release downloads and API rate limits | `${{ github.token }}` | No |
| `plugins` | Newline- or comma-separated plugin refs to install (e.g. `kapi-bowrain`) | — | No |
| `auth-token` | Bowrain server JWT, exported as `BOWRAIN_AUTH_TOKEN` | — | No |
| `server` | Bowrain server URL, exported as `BOWRAIN_SERVER_URL` | — | No |

## Outputs

| Output | Description |
|--------|-------------|
| `version` | Installed version (e.g. `1.0.0`) |
| `cache-hit` | Whether the plugin cache was hit |

## How it works

1. **Resolve version** — `latest` resolves the newest *stable CLI* release (a `vX.Y.Z` tag). It deliberately does not use GitHub's "latest release" flag: the same repository publishes plugin and app releases (`check-v0.1.0`, `asr-v0.1.1`, `bowrain-v…`), and that flag lands on whichever was published last. Pinned versions pass through.
2. **Cache check** — restores a cached binary keyed on `kapi-{version}-{os}-{arch}`.
3. **Download + verify** (on cache miss) — downloads the archive and `checksums.txt` from the GitHub release, verifies the SHA-256 checksum, and extracts the binary.
4. **Add to PATH** — makes `kapi` available to all subsequent steps.
5. **Configure auth** (optional) — exports `BOWRAIN_AUTH_TOKEN`/`BOWRAIN_SERVER_URL` when `auth-token` is set.
6. **Install plugins** (optional) — installs each ref in `plugins` via `kapi plugins install`, cached keyed on the plugin set + OS + arch.

## Caching

The binary is cached keyed on version + OS + arch; plugins are cached keyed on the plugin set + OS + arch. Both skip their download step on a cache hit.

## Platform support

| Runner OS | Architectures |
|-----------|---------------|
| Linux | amd64, arm64 |
| macOS | arm64 (Apple silicon; no Intel build is published) |
| Windows | amd64, arm64 |

## License

Apache-2.0
