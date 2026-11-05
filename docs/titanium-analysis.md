# android-titanium-browser — recon notes

Fork created: https://github.com/chierce/android-titanium-browser (branch `fork-ci`)
Local checkout: `C:\Users\User\Documents\titanium-recon\android-titanium-browser`
WSL staging: `~/titanium/android-titanium-browser` (944 GB free, 12 cores, 7 GB RAM)

Upstream: Chromium-based Android browser derived from **GrapheneOS Vanadium**, GPL-2.0,
extensions support, published on Play + GitHub Releases. `vanadium/` is a git
submodule pinned to `99a6c82` (GrapheneOS/Vanadium), holding **302 patches**.

## What build.sh actually does

| Stage | Command | Consequence |
| --- | --- | --- |
| deps | `apt-get install` + i386 multiarch | needs sudo, non-interactive |
| checkout | `git fetch --depth 1 refs/tags/$VERSION` where VERSION is grepped from `vanadium/args.gn` | source ~40-60 GB |
| patch | deletes a list of Vanadium patches (Trichrome targets, languages, JS optimizer, component updates, PDF, config-app, NTP cards, predictive back), then `git am` the rest | 302 → fewer; failures here abort the build |
| sync | `gclient sync -D --no-history --nohooks` + `runhooks` + `install-build-deps.sh` | hooks run `extensions/bundle.py` (downloads titanium.crx) and the filter-list fetch; needs network |
| config | `cp args.gn out/Default; gn gen` | one config per ABI |
| build | `autoninja -C out/Default chrome_public_apk` ×2 (`arm`, then `arm64`) + `chrome_public_bundle` | the expensive part |
| sign | `apksigner` / `jarsigner` with `keys/test.jks` | from `LOCAL_TEST_JKS`/`STORE_TEST_JKS` secrets |

## args.gn highlights (67 lines)

`is_official_build = true`, `is_debug = false`, `symbol_level = 1`, `is_component_build = false`,
`target_os = "android"`, `target_cpu = "arm"` (build.sh flips it to `arm64` for the second pass),
`is_desktop_android = true` (desktop-style UI on Android), `use_siso = true`,
`proprietary_codecs = true` + `ffmpeg_branding = "Chrome"` (H.264/AAC), `enable_av1_decoder` +
`enable_dav1d_decoder`, `v8_enable_drumbrake`, `generate_linker_map = true`,
`chrome_public_manifest_package = "io.github.jqssun.helium"`, and the ARCORE/VR/remoting/reporting
features switched off. Google API key/client id/secret are literally `"x"` — the build ships
without Google service keys, which is why it can't sign into Chrome Sync.

## Patch set shape (302 files, categorised by subject)

| Bucket | Count | Examples |
| --- | --- | --- |
| features / flags | 98 | fixed flag expiry (`expiry_milestone: -1`), baseline configs, feature toggles |
| build system | 71 | custom APK targets, secondary-ABI fixes, versionCode for 64-bit-only builds |
| webview | 21 | 64-bit WebView processes, hardened malloc, cookie policy |
| privacy / network | 19 | NetworkAnonymizationKey, network-state partitioning |
| upstream re-apply | 11 | re-lands GrapheneOS carries over new Chromium |
| security hardening | 9 | stack-clash protection, `-fstack-protector-strong`, `-fwrapv`, `-ftrivial-auto-var-init=zero`, shadow-call-stack on arm64 |
| extensions | 7 | bundled extension staging, external-pref loader hook, safety-check bypass for bundled ext |
| branding | 6 | Vanadium → Titanium strings, icons tinted navy |
| other | 108 | bugfixes, config-app plumbing, NTP/omnibox tweaks |

`patch.sh` (23 KB of `sed -i`) is where the product identity lives: themed icons,
`android:extractNativeLibs="false"`, PDF mime type, scheme guards in `LaunchIntentDispatcherHooks`,
omnibox site search flipped to prod, DevTools frontend + media picker enabled under
`IS_DESKTOP_ANDROID`, and `chrome_paths.cc` repointed from `DIR_MODULE` to `DIR_USER_DATA` so
bundled extensions load from user data.

## CI reality

Upstream `build.yml` defaults to `runs-on: self-hosted` and needs `LOCAL_TEST_JKS` /
`STORE_TEST_JKS`. GitHub-hosted `ubuntu-latest` has ~14 GB free disk: a Chromium Android
checkout alone exceeds it, so a fork running there dies in `gclient sync`, not in ninja.
That is why `ci/preflight.sh` exists and exists *before* the build job.

Fork deliverables on branch `fork-ci`:

- `ci/preflight.sh` — disk/cpu/ram/toolchain gate, fails with the number you're short by
- `ci/make-dev-keys.sh` — generates a throwaway RSA keystore + `local.properties`, prints the
  two base64 blobs upstream CI expects
- `ci/build-fork.yml` — **template**, not yet active: `workflow_dispatch` only, never commits or
  publishes, accepts a runner label, generates dev keys when secrets are missing, uploads
  artifacts, and writes a provenance note when the signature is self-made

To activate it: it must live at `.github/workflows/`, and pushing workflow files requires the
`workflow` OAuth scope:

```bash
gh auth refresh -s workflow
git mv ci/build-fork.yml .github/workflows/build-fork.yml
git commit -m "ci: activate fork build workflow" && git push
```

## Machine feasibility (measured today)

| Target | Disk free | Cores | RAM | Verdict |
| --- | --- | --- | --- | --- |
| Windows C: | 131 GB | 12 | 15 GB | too tight for two ABIs; Linux-only scripts don't run natively |
| WSL2 Ubuntu | 944 GB | 12 | 7 GB (default cap) | viable for one ABI; bump RAM to 12 GB first |
| ubuntu-latest CI | ~14 GB | 4 | 16 GB | not viable |
| self-hosted CI | user-supplied | — | — | the upstream path |

Expected: 2-6 h wall clock for arm64 only after the ~40-60 GB `gclient sync`, with
`MAX_JOBS` around 8-10 on 12 cores and 12 GB RAM. Link step is the OOM risk, not compile.