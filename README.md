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

### Run a flow

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
      version: "1.2.0-rc32"
      auth-token: ${{ secrets.BOWRAIN_AUTH_TOKEN }}
      server: https://your.bowrain.server

  - run: kapi up
```

The newest stable release, which `latest` installs, has no `kapi up`, so this example pins the prerelease that has it.

`kapi up` runs the kapi loop: with the bowrain plugin installed and a `server:` block in the recipe, it pushes, catches up on the server, and pulls the produced targets back. To run it and commit the results, pair this with [`kapi-action`](https://github.com/neokapi/kapi-action).

## Inputs

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `version` | Kapi CLI version (e.g. `1.1.0`), or `latest` for the newest stable CLI release | `latest` | No |
| `token` | GitHub token for release downloads and API rate limits | `${{ github.token }}` | No |
| `plugins` | Newline- or comma-separated plugin refs to install, as the registry names them (`bowrain`, `okapi-bridge`; a `kapi-` prefix is stripped). Pass `''` to install nothing | `bowrain` | No |
| `auth-token` | Bowrain server JWT, exported as `BOWRAIN_AUTH_TOKEN` | — | No |
| `server` | Bowrain server URL, exported as `BOWRAIN_SERVER_URL` | — | No |
| `cache-tm` | Carry kapi's parse cache (`.kapi/work/cache/docs`) between runs with the job cache; see [Project parse cache](#project-parse-cache). Runs only when a `kapi.yaml` recipe (or legacy `*.kapi`) is present. Set `false` to disable | `true` | No |
| `project-dir` | Directory holding the `kapi.yaml` project whose parse cache is carried between runs | `.` | No |

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
7. **Restore the project parse cache** (when a `kapi.yaml` recipe, or legacy `*.kapi`, is present): restores `.kapi/work/cache/docs` from the job cache, and saves it again at job end under a key unique to the job and run attempt. See [Project parse cache](#project-parse-cache). Disable with `cache-tm: false`.

## Caching

The binary is cached keyed on version + OS + arch; plugins are cached keyed on the plugin set + OS + arch. Both skip their download step on a cache hit.

### Project parse cache

kapi keeps the state it derives out of git, under `.kapi/work/` (the project's `.kapi/.gitignore` ignores `work/` and `filters.local.json`). With `cache-tm` on and a recipe in `project-dir`, the action restores one directory of it, `.kapi/work/cache/docs`, before your steps run, and `actions/cache` saves it again when the job ends. kapi records there how it parsed each source and target file, so a later run can replay a file instead of parsing it again.

A restored parse cache does not change any result. kapi keys each entry by the file's path and content hash, the parse configuration, the recipe and the kapi build, and parses the file again when any of them differs. The test workflow checks this on every change: with the cache restored, `kapi status`, `kapi check`, `kapi check --ship` and `kapi up` must match a cold run exactly, in exit codes, output and every file written, and they must still match after the source changes.

Everything else under `.kapi/` stays out of the cache:

- The content memory, terms, voice profile and unit-state record are committed under `.kapi/`, so the checkout already holds them, and kapi builds its local store from them.
- `.kapi/work/store.db` also holds stored targets and staged review decisions. Restored from an earlier run, it reports targets the checkout does not hold, and `kapi status`, `kapi check --ship` and `kapi up` report differently than they would on a cold run.
- `.kapi/work/cache/extractions/` holds `kapi extract` batches for `kapi merge`, and `.kapi/work/cache/redaction/` and `.kapi/work/vault/` hold withheld original values.
- `.kapi/work/cache/sync-cache.json` and `.kapi/work/cache/refs.json` hold server sync state, including a claim token.

The cache key holds the runner OS, the resolved kapi version and the ref, so a new kapi version starts from an empty cache. How much time the cache saves depends on the formats: container formats such as DOCX replay faster than they parse, while JSON and Markdown parse about as fast as they replay.

## Platform support

| Runner OS | Architectures |
|-----------|---------------|
| Linux | amd64, arm64 |
| macOS | arm64 (Apple silicon; no Intel build is published) |
| Windows | amd64, arm64 |

## License

Apache-2.0
