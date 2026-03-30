# setup-kapi

GitHub Action for installing the [kapi CLI](https://github.com/neokapi/neokapi) in CI workflows.

Downloads the correct binary for the runner platform, verifies SHA-256 checksums, and caches between runs.

## Usage

### Basic

```yaml
steps:
  - uses: neokapi/setup-kapi@v1
    with:
      token: ${{ secrets.NEOKAPI_GITHUB_TOKEN }}
```

### Pinned version

```yaml
steps:
  - uses: neokapi/setup-kapi@v1
    with:
      token: ${{ secrets.NEOKAPI_GITHUB_TOKEN }}
      version: "0.5.0"
```

### Run a localization pipeline

```yaml
steps:
  - uses: neokapi/setup-kapi@v1
    with:
      token: ${{ secrets.NEOKAPI_GITHUB_TOKEN }}

  - run: kapi run
```

## Inputs

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `version` | Kapi CLI version (e.g. `0.5.0` or `latest`) | `latest` | No |
| `token` | GitHub token with read access to `neokapi/neokapi` releases | — | Yes |

## Outputs

| Output | Description |
|--------|-------------|
| `version` | Installed version (e.g. `0.5.0`) |

## How it works

1. **Resolve version** — `latest` queries the GitHub API for the most recent release; pinned versions pass through.
2. **Cache check** — restores a cached binary keyed on `kapi-{version}-{os}-{arch}`.
3. **Download + verify** (on cache miss) — downloads the archive and `checksums.txt` from the GitHub release, verifies the SHA-256 checksum, and extracts the binary.
4. **Add to PATH** — makes `kapi` available to all subsequent steps.

## Caching

The action caches the binary keyed on version + OS + arch. Skips download and checksum verification on cache hit.

## Platform support

| Runner OS | Architectures |
|-----------|---------------|
| Linux | amd64, arm64 |
| macOS | amd64, arm64 |
| Windows | amd64, arm64 |

## License

Apache-2.0
