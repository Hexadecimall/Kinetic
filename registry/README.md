# Kinetic plugin registry

The public catalog is generated from `registry/entries/` and served by GitHub Pages at
`https://hexadecimall.github.io/Kinetic/plugins/index.json` after Pages is enabled. Plugin binaries
are hosted as public GitHub Release assets in each publisher's repository. Kinetic's catalog stores
metadata and SHA-256 hashes, not executable binaries. No custom upload server or account database
is involved.

## Publish a plugin

1. Build a macOS arm64 `.dylib` against [`pluginApi.h`](../include/kinetic/pluginApi.h), and test it
   locally under `~/.kinetic/plugins/`.
2. Upload that exact binary to a public GitHub Release in a repository owned by the publishing
   GitHub account. Do not replace the asset after publishing; release entries are immutable.
3. Get the account's numeric GitHub ID from `https://api.github.com/users/LOGIN`. The ID, not the
   mutable login spelling, is the registry's publisher identity.
4. Create a release entry and regenerate the index:

   ```sh
   python3 scripts/pluginRegistry.py draft \
     --id example.my-plugin \
     --name 'My Plugin' \
     --summary 'What the plugin adds' \
     --github-login example \
     --github-id 123456 \
     --version 0.1.0 \
     --asset /path/to/myPlugin.dylib \
     --release-url https://github.com/example/my-plugin/releases/download/v0.1.0/myPlugin.dylib
   python3 scripts/pluginRegistry.py check
   ```

5. Open a pull request containing the new entry and generated `registry/index.json`. GitHub is the
   publisher sign-in and review surface. CI compares the submitted GitHub ID and login with the PR
   author, rejects changes to existing release entries, downloads the public release asset, and
   verifies its size, arm64 Mach-O header, and SHA-256 before the catalog can deploy.

Only macOS arm64 and plugin ABI 1 are accepted in this first registry schema. Assets must be at
most 32 MiB. A new version adds a new JSON file; it never edits a published release. The same
GitHub account must own every version of a plugin ID. A different owner needs a maintainer-reviewed
transfer mechanism that does not exist yet.

## Official label

The submitted release entry has no `official` field. The generated catalog sets `official` only
when `registry/official.json` maps the plugin ID to the same numeric GitHub publisher ID. A
non-owner PR cannot change that policy. The `kinetic.*` namespace is reserved for Official
plugins. Policy and publishing automation are listed in `CODEOWNERS`. The protected `main` branch
requires both the CI `validate` and `Plugin Registry` `registryValidate` checks. The registry check
runs on every pull request, including ones without catalog changes. Human review can become a
required rule once another maintainer is available to approve the owner's pull requests.

The bundled first-party C/C++ Support plugin has a separate, manual
`Publish C/C++ Support` workflow. It tests and builds the plugin on macOS, verifies the signed
arm64 asset and its public-path hygiene, then creates `cpp-support-v0.1.0` with an immutable
`libkineticCppSupport.dylib` release asset. The workflow prints the uploaded size and SHA-256;
add the catalog entry only after those remote bytes pass `verify-assets`. Re-running the workflow
will not replace an existing asset.

“Official” means Kinetic project approval, not a claim that native code is sandboxed or risk-free.
The editor does not yet browse or install from this catalog. A future installer must verify the
downloaded binary against the catalog checksum before placing it in `~/.kinetic/plugins/`, and
must tell the user the publisher and trust status before installation.

## Maintenance

`python3 scripts/pluginRegistry.py check` verifies the checked-in index. `verify-assets` fetches
every release and compares its bytes with the catalog. `build --output PATH` writes a deterministic
index to any target path. The Pages workflow publishes only after validation on `main`; PRs have
read-only GitHub permissions and never deploy. Enable Pages with GitHub Actions as its source, and
keep the default branch protected before treating the hosted catalog as a trust root.
