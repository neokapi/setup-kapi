# setup-kapi

GitHub Action for installing the [kapi CLI](https://github.com/neokapi/neokapi) in CI workflows.

Downloads the correct binary for the runner platform, verifies SHA-256 checksums, caches between runs, installs kapi plugins (the bowrain plugin by default), and configures server authentication.

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

### With server auth

The bowrain plugin is installed by default, so a server-connected project only
needs credentials:

```yaml
steps:
  - uses: neokapi/setup-kapi@v1
    with:
      auth-token: ${{ secrets.BOWRAIN_AUTH_TOKEN }}
      server: https://your.bowrain.server

  - run: kapi up
```

`kapi up` runs the kapi loop: with the bowrain plugin installed and a `server:` block in the recipe, it pushes, catches up on the server, and pulls the produced targets back. To run it and commit the results, pair this with [`kapi-action`](https://github.com/neokapi/kapi-action).

## Inputs

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `version` | Kapi CLI version (e.g. `1.1.0`), or `latest` for the newest stable CLI release | `latest` | No |
| `token` | GitHub token for release downloads and API rate limits | `${{ github.token }}` | No |
| `plugins` | Newline- or comma-separated plugin refs to install, as the registry names them (`bowrain`, `okapi-bridge`; a `kapi-` prefix is stripped). Pass `''` to install nothing | `bowrain` | No |
| `auth-token` | Bowrain server JWT, exported as `BOWRAIN_AUTH_TOKEN` | — | No |
| `server` | Bowrain server URL, exported as `BOWRAIN_SERVER_URL` | — | No |
| `cache-tm` | Restore/persist the project translation memory across runs via the job cache (out of git). Runs only when a `*.kapi` recipe is present. Set `false` to disable | `true` | No |
| `project-dir` | Directory holding the `.kapi` project for the TM cache | `.` | No |

## Outputs

| Output | Description |
|--------|-------------|
| `version` | Installed version (e.g. `1.0.0`) |
| `cache-hit` | Whether the plugin cache was hit |

### With the Okapi bridge (Java plugin)

The `okapi-bridge` plugin runs Okapi Framework filters as a Java subprocess,
so the runner needs a JVM — Java 11+, or Java 17+ for Okapi 1.48.0 and later.
GitHub's hosted Ubuntu runners ship a default JDK; pin one explicitly with
`setup-java` when you need a specific version:

```yaml
steps:
  - uses: actions/setup-java@v4
    with:
      distribution: temurin
      java-version: "17"

  - uses: neokapi/setup-kapi@v1
    with:
      plugins: |
        bowrain
        okapi-bridge
```

The plugin (bridge JARs included) is cached like any other, keyed on the
plugin set + OS + arch, so the download cost is paid once per runner
image.

## How it works

1. **Resolve version** — `latest` resolves the newest *stable CLI* release (a `vX.Y.Z` tag). It deliberately does not use GitHub's "latest release" flag: the same repository publishes plugin and app releases (`check-v0.1.0`, `asr-v0.1.1`, `bowrain-v…`), and that flag lands on whichever was published last. Pinned versions pass through.
2. **Cache check** — restores a cached binary keyed on `kapi-{version}-{os}-{arch}`.
3. **Download + verify** (on cache miss) — downloads the archive and `checksums.txt` from the GitHub release, verifies the SHA-256 checksum, and extracts the binary.
4. **Add to PATH** — makes `kapi` available to all subsequent steps.
5. **Configure auth** (optional) — exports `BOWRAIN_AUTH_TOKEN`/`BOWRAIN_SERVER_URL` when `auth-token` is set.
6. **Install plugins** — installs each ref in `plugins` (default: `bowrain`) via `kapi plugins install`, cached keyed on the plugin set + OS + arch. Refs use the registry names; a `kapi-` binary prefix is stripped (`kapi-bowrain` → `bowrain`).
7. **Restore project TM cache** (when a `*.kapi` recipe is present) — restores the latest translation memory for the branch from the job cache and, via a run-unique key, saves the grown TM back at job end. The TM is **derived state kept out of git**: it accumulates leverage across runs without being committed, and a cold cache simply rebuilds from the committed translations. No commits, no locking (per-branch, last-write-wins). Disable with `cache-tm: false`.

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
