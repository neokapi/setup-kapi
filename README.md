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
| `plugins` | Newline- or comma-separated plugin refs to install, as the registry names them (`bowrain`, `okapi-bridge`; a `kapi-` prefix is stripped). Pass `''` to install nothing. No Bowrain plugin build is listed for Windows before the next kapi release, so a Windows job sets `plugins: ""` until then | `bowrain` | No |
| `auth-token` | Bowrain server JWT, exported as `BOWRAIN_AUTH_TOKEN` | — | No |
| `server` | Bowrain server URL, exported as `BOWRAIN_SERVER_URL` | — | No |
| `parse-cache` | Keep kapi's parse cache between runs, so a later run replays files it already parsed; see [Project parse cache](#project-parse-cache). Runs only when a `kapi.yaml` recipe (or legacy `*.kapi`) is present. Set `false` to turn it off | `true` | No |
| `cache-tm` | Deprecated name of `parse-cache`. When set, it decides in place of `parse-cache`, and the action prints a warning | `''` | No |
| `project-dir` | Directory holding the `kapi.yaml` project whose parse cache is kept between runs | `.` | No |

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

The plugin (bridge JARs included) is cached like any other, so the download
is paid once for each kapi version and plugin release.

## How it works

1. **Resolve version**: `latest` resolves the newest *stable CLI* release (a `vX.Y.Z` tag). It deliberately does not use GitHub's "latest release" flag: the same repository publishes plugin and app releases (`check-v0.1.0`, `asr-v0.1.1`, `bowrain-v…`), and that flag lands on whichever was published last. Pinned versions pass through.
2. **Cache check**: restores a cached binary keyed on `kapi-{version}-{os}-{arch}`.
3. **Download + verify** (on cache miss): downloads the archive and `checksums.txt` from the GitHub release, verifies the SHA-256 checksum, and extracts the binary.
4. **Add to PATH**: makes `kapi` available to all subsequent steps.
5. **Configure auth** (optional): exports `BOWRAIN_AUTH_TOKEN`/`BOWRAIN_SERVER_URL` when `auth-token` is set.
6. **Install plugins**: installs each ref in `plugins` (default: `bowrain`) via `kapi plugins install`, cached as described below. Refs use the registry names; a `kapi-` binary prefix is stripped (`kapi-bowrain` → `bowrain`).
7. **Restore the project parse cache** (when a `kapi.yaml` recipe, or legacy `*.kapi`, is present): restores kapi's parse cache from the job cache, and saves it again at job end under a key unique to the job and run attempt. See [Project parse cache](#project-parse-cache). Disable with `parse-cache: false`.

## Caching

The binary is cached keyed on version + OS + arch. Plugins are cached keyed on the resolved kapi version, the plugin set, each requested plugin's registry entry, OS and arch, so a cache restores only the plugins a fresh install by that kapi would choose: a new kapi release or a new plugin release starts from an empty plugin cache. Both skip their download step on a cache hit.

### Project parse cache

kapi records how it parsed each source and target file, so a later run can replay a file instead of parsing it again. With `parse-cache` on and a recipe in `project-dir`, the action restores that parse cache before your steps run, and `actions/cache` saves it again when the job ends.

The action sets `KAPI_PARSE_CACHE_DIR` to a directory under `runner.temp` for the rest of the job, and caches that directory together with `<project-dir>/.kapi/work/cache/docs`. A kapi that reads the variable keeps its parse cache there; kapi 1.3 and earlier keep it in the checkout. If your workflow sets `KAPI_PARSE_CACHE_DIR` itself, the action keeps your value and caches it when it lies under `runner.temp`. On another CI system, set `KAPI_PARSE_CACHE_DIR` to a fixed absolute directory outside the project and cache that directory. Let kapi create it, which it does with access for your user only. kapi stops with an error when the directory is inside the project, is a link, belongs to another user, or gives group or other users any access.

A restored parse cache does not change any result. kapi keys each entry by the file's path and content hash, the parse configuration, the recipe and the kapi build, and parses the file again when any of them differs. The test workflow checks this on every change: with the cache restored, `kapi status`, `kapi check`, `kapi check --ship` and `kapi up` must match a cold run exactly, in exit codes, output and every file written, and they must still match after the source changes.

The action carries the parse cache and nothing else. The project store holds this checkout's blocks and the targets a run wrote, and a restored copy changes what `kapi status`, `kapi check --ship` and `kapi up` report. The extraction batches, the redaction vault and the sync state (with its claim token) belong to the checkout that wrote them. The project's context (its terms, voice profiles, content memory and recorded decisions) lives in kapi's workspace and moves between machines through a context backend (kapi 1.3 and later). A job that needs it runs `kapi context pull` before kapi works and `kapi context push` after a run records something. [`kapi-action`](https://github.com/neokapi/kapi-action)'s `context-sync` input runs both around its command, or your workflow can run them as steps of its own.

Each run saves its own cache, keyed by the runner OS, the resolved kapi version, the ref, the job and the run. A run restores the newest cache for the same kapi version, from its own ref first. The key does not change with your source files: a cache from before a source edit still holds the entries for every file the edit left alone. A new kapi version starts from an empty cache. How much time the cache saves depends on the formats: container formats such as DOCX replay faster than they parse, while JSON and Markdown parse about as fast as they replay.

kapi trusts what it finds in its parse cache, so who can write the cache decides whether a restored entry can be trusted. GitHub scopes caches by branch: a run restores only caches saved on its own branch, on the default branch, or, for a pull request, on its base branch. A cache saved by a pull request, including one from a fork, is never restored on the default branch. A `pull_request_target` run works in the base branch's scope, so there the action restores the parse cache and does not save it. Any other workflow that runs untrusted code with this action can write to the cache of the branch it runs on; set `parse-cache: false` in such a workflow.

## Platform support

| Runner OS | Architectures |
|-----------|---------------|
| Linux | amd64, arm64 |
| macOS | arm64 (Apple silicon; no Intel build is published) |
| Windows | amd64, arm64 |

## License

Apache-2.0
