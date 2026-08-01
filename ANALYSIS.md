# Telegram Desktop → ppa:lightofmysoul/tg — feasibility analysis

Date: 2026-08-01. Nothing installed, nothing built — research only.

## 0. Decisions taken

| | |
|---|---|
| target series | **resolute 26.04** only |
| target version | **latest upstream (v7.0.7)**, not Debian's 5.7.2 |
| tg_owt | **standalone source package, our own** — native, built from the upstream tree on branch `tgowt_ubuntu` |
| tde2e | **second standalone package** — mandatory for tdesktop 7.x, packaged nowhere; `tdlib/td` @ `51743df`, `TD_E2E_ONLY=ON`, branch `tde2e_ubuntu` |
| everything else | no separate packaging — resolute has it, or it vendors in-tree |
| API credentials | upstream's public snap creds `611335` — no personal registration |
| PPA processors | `amd64`, `arm64` enabled ✅ (`amd64v3` also on — see §2) |

## 1. Verdict

Feasible, but **not** with the `kwin-vr` recipe (pull Ubuntu's source, apply patches).
Ubuntu has no `telegram-desktop` source to pull. The base must come from **Debian**,
and one missing dependency (`libtgowt`) must be built in the PPA first.

Shape: a **two-package PPA** for **resolute (26.04)**, amd64 + arm64. The webrtc half is
near-free (Debian's `libtgowt` is 3 trivial commits from what 7.0.7 wants). The whole job is
reconciling Debian's `telegram-desktop` packaging with 21 months of upstream churn.

## 2. Hard facts gathered

### Ubuntu has nothing to rebase on
| item | state |
|---|---|
| `telegram-desktop` in Ubuntu | last published `4.5.3+snap-0ubuntu1` in **lunar**, **Deleted 2023-01-15** (replaced by the snap) |
| `libtgowt` in Ubuntu | last published in lunar/mantic, **Deleted 2023-05-07** |
| consequence | `pull-lp-source telegram-desktop` fails; no Ubuntu delta to preserve |

### Debian is the viable base and already builds on arm64
| package | version (sid/forky) | arches built |
|---|---|---|
| `telegram-desktop` | `5.7.2+ds-5` (uploaded 2026-04-21) | amd64 arm64 armhf i386 loong64 ppc64el riscv64 |
| `libtgowt` | `0~git20251117.d067233+dfsg-3` | + s390x |

Source format `3.0 (quilt)`, 24 patches, maintainer Nicholas Guriev, active.
`debian/rules` already has an **Ubuntu-specific branch** (disables LTO: "requires more than 8 GB of RAM").

### Build-dependency audit against Ubuntu 26.04 (resolute)
Checked all 46 `telegram-desktop` build-deps and all 21 `libtgowt` build-deps against the
resolute main+universe amd64 package index.

**Exactly one gap: `libtgowt-dev`.** Everything else resolves, including the non-obvious ones:
- `gir1.2-gio-2.0-dev` → provided by `gir1.2-glib-2.0-dev (2.88.0-1)`
- `node-types-lodash.isequal` → satisfied via `Provides`
- `cppgir 2.0+git20250629` → present on **both** amd64 and arm64
- `libada-url-dev 3.4.3`, `libkf6coreaddons-dev 6.24.0`, `qt6-base-private-dev 6.10.2`, `node-prismjs`, `libmsgsl-dev`, `libqrcodegencpp-dev`, `librlottie-dev`, `libminizip-dev` — all present

All of `libtgowt`'s own deps are present too (`libabsl-dev`, `libyuv-dev`, `libopenh264-dev`,
`libsrtp2-dev`, `libvpx-dev`, `libpipewire-0.3-dev`, …).

→ **Build `libtgowt` in the PPA, then `telegram-desktop` against it.** Launchpad handles the
ordering itself (dep-wait + auto-retry once libtgowt publishes).

### tg_owt: standalone, and Debian's snapshot is already the right one
Cloned `desktop-app/tg_owt` locally to check (`/mnt/more_data/tg/tg_owt`):

| | commit | date |
|---|---|---|
| pinned by tdesktop 7.0.7 (`Telegram/build/prepare/prepare.py:1700`) | `89df288` | 2026-04-09 |
| current `origin/master` | `89df288` | same commit |
| Debian `libtgowt 0~git20251117.d067233+dfsg-3` | `d067233` | 2025-11-17 |

**3 commits apart**, 12 lines total. And Debian already carries two of the three as quilt
patches — `Fix-building-with-Pipewire-1.5.81-and-later`, `Fixed-missing-include-cstring` —
*plus* `Fix-building-with-GCC-16` and `Migrate-to-OpenSSL-4.0.0`, which upstream does not have.
Only the `ABSL_ATTRIBUTE_LIFETIME_BOUND` one-liner (`src/api/candidate.h`) is absent, and
resolute's abseil (20260107) is older than the sid abseil (20260526) Debian builds against,
so it is unlikely to be needed. Add it as a patch if the build says otherwise.

**Superseded — we package upstream directly instead.** Importing Debian's package
works (validated: it builds unmodified on resolute), but it is pinned to a 2025 base with
the newer commits as patches, and its `+dfsg` repack must strip RNNoise for DFSG reasons,
costing the RNN voice-activity-detection path in WebRTC's AGC2.

Building the upstream tree turned out to be **simpler** than importing Debian's:
`cmake/external.cmake` already probes for system libraries, so Ubuntu's `libabsl-dev` and
`libsrtp2-dev` are picked up automatically, crc32c and libyuv come from bundled submodules,
and RNNoise builds as shipped. **Zero patches.** Debian's remaining patches target toolchains
newer than resolute has (GCC 16, OpenSSL 4) or architectures we do not build.

Result is layout-identical to Debian's — same `libtg_owt.a`, same `cmake/tg_owt/` config,
same include tree — plus 27 libyuv and 2 RNNoise headers. Anything build-depending on
Debian's `libtgowt-dev` works against it unchanged. See `tg_owt/PACKAGING.md`.

Either way, tg_owt stays a separate source package rather than being bundled into tdesktop:
- `libtgowt-dev` is a **static** library — no shared lib, no runtime package. "Separate" means
  separate *source* package; the tdesktop binary statically links it. Bumping tg_owt therefore
  requires rebuilding tdesktop, which is what Debian's `cpplibs:Built-Using` records (their
  `5.7.2+ds-4` upload was exactly such a rebuild).
- Debian's `telegram-desktop` packaging already `Build-Depends: libtgowt-dev`. Bundling means
  diverging from the packaging we are reusing, for nothing.
- During the 7.0.x port each tdesktop build is ~1 h; not recompiling webrtc every iteration
  matters.
- Same split as Gentoo (`media-libs/tg_owt`), Arch, Fedora.

### Resolute is slightly *behind* sid — the easy direction
| | Debian sid | Ubuntu resolute |
|---|---|---|
| gcc | 15.2.0 | 15.2.0 |
| qt6-base | 6.10.2+dfsg-15 | 6.10.2+dfsg-7 |
| cmake | 4.3.4 | 4.2.3 |
| ffmpeg (libavcodec) | 8.1.2 | 8.0.1 |
| abseil | 20260526.0 | 20260107.0 |
| openssl | 3.6.3 | 3.5.5 |
| pipewire | 1.6.8 | 1.6.2 |
| libyuv | 0.0.1949 | 0.0.1922 |

Debian's packages are built against newer everything, so we compile against slightly older
libraries — fewer new-API breakages, not more.

### Other Ubuntu series are not worth it
| series | verdict |
|---|---|
| **resolute 26.04** | ✅ target |
| stonking 26.10 (devel) | ✅ possible, add later |
| noble 24.04 | ❌ no `libkf6coreaddons-dev` (no KF6), no `libada-url-dev`, Qt6 is **6.4.2** — would mean backporting half of KDE |
| jammy and older | ❌ hopeless |

### Build cost — real numbers from Debian's buildds
| package | arch | time | disk |
|---|---|---|---|
| telegram-desktop | amd64 | 62 min | 27 GB |
| telegram-desktop | arm64 | 55 min | 27 GB |
| libtgowt | amd64 | 6.7 min | 1.5 GB |
| libtgowt | arm64 | 6.2 min | 1.5 GB |

Launchpad kills a build after **150 min with no output** (LP #1983155). A ninja build prints
continuously, so this is not a risk. Comfortable margin.

### PPA configuration — needs fixing before first upload
Queried `https://api.launchpad.net/devel/~lightofmysoul/+archive/ubuntu/tg`:

| setting | current | note |
|---|---|---|
| processors | `amd64`, `arm64`, `amd64v3` | amd64 enabled 2026-08-01 ✅ |
| authorized_size | 8192 MiB | watch it |
| build/publish debug symbols | true / true | consider **off** |
| status | Active, public, virtualized | ok |

- `amd64v3` is the x86-64-v3 *architecture variant* (client opt-in). Leaving it on costs a
  **third ~1 h build per upload** plus another copy of the binaries against the 8 GiB quota,
  and only users who explicitly enabled amd64v3 would ever install it. Marginal AVX2 win —
  suggest turning it off until the pipeline is stable.
- installed sizes: `telegram-desktop` 114 MB, `libtgowt-dev` 38 MB. dbgsym for a C++ app this
  size is on the order of a GB per arch — that is what will eat the 8 GiB quota.

### The version gap is the real work
| | |
|---|---|
| Debian ships upstream | **v5.7.2**, tagged **2024-11-05** |
| upstream latest | **v7.0.7**, tagged **2026-08-01** (today) |
| gap | **6408 commits**, ~21 months |
| new third-party submodules since 5.7.2 | `lib_translate`, `cmark-gfm`, `libcbor`, `libfido2`, `MicroTeX`, `TooManyCooks` |
| dropped since 5.7.2 | `dispatch`, `jemalloc`, `libtgvoip` |

Of the new ones, Ubuntu already has `libcmark-gfm-dev`, `libcbor-dev`, `libfido2-dev`
(upstream added "Support packaged fido2" two commits ago). `MicroTeX` and `TooManyCooks` are
not packaged anywhere → must stay vendored in the orig tarball.

Debian's 24 patches would need rebasing. Rough triage: the compat ones
(`Fix-build-with-Qt-6.9`, `Compatibility-with-FFmpeg-8`, `1005/1006 missing includes`,
`Include-minizip-dir`, `Revert-Workaround-cmake-bug-25222`) are probably obsolete upstream by
now; the distro-policy ones must be carried and reworked: `System-wide-cppgir`,
`Skip-CLD3`, `Packed-resources`, `Really-disable-crash-reports`, `No-random-popups`,
`XdgDesktopPortal`, `Generate-libprisma-grammars`, `Exclude-IV-resources`,
`Disable-register-custom-scheme`. Expect ~10 surviving patches, most needing real work.

Good news: upstream publishes **`tdesktop-<ver>-full.tar.gz`** release tarballs with all
submodules included — **77.6 MB for v7.0.7** (67.1 MB for 5.7.2). No recursive clone needed,
and Debian's `d/watch` already consumes exactly this file. `mk-origtargz` + the
`Files-Excluded:` list in `d/copyright` produces the `+ds` tarball.

### Launchpad builders have no network
Everything must come from the archive or the orig tarball. Upstream's own
`Telegram/build/prepare/linux.sh` (which downloads and builds ~40 libs) is unusable on
Launchpad. The Debian route — system libs + one static `libtgowt` — is the only sane one.

### API credentials — use upstream's public snap creds
There are three sets in play:

| creds | source | use? |
|---|---|---|
| `611335` / `d524b414d21f4d37f08684c1df41ac9c` | upstream's own `snap/snapcraft.yaml:56-57` | ✅ **this one** |
| `50322` / `9ff1a639196c0779c86dd661af8522ba` | Debian's registered app (`d/rules`) | ❌ not ours |
| `17349` / `344583e45741c457fe1862106095a5eb` | `docs/api_credentials.md` | ❌ **TEST ONLY** — upstream: "Your users will start getting internal server errors on login" |

`611335` is published by Telegram themselves in the tdesktop repo for the official snap build.
Gentoo's ebuild uses exactly these as its default
(`/var/db/repos/gentoo/net-im/telegram-desktop/telegram-desktop-7.0.2.ebuild:226-227`, only
overridden if `MY_TDESKTOP_API_ID` is set — not set on this machine), so the Telegram Desktop
running here is already on them. Arch and others do the same.

Caveat: shared by many distro builds, so if Telegram ever throttles it we are affected along
with Gentoo/Arch users. Reversible — it is one cmake variable in `d/rules`.

→ replace Debian's `50322` with `611335` in `debian/rules`.

## 3. Layout — one clone per package, packaging on a branch

```
/mnt/more_data/tg/
├── ANALYSIS.md      this file
├── status.sh        pins vs packaged vs PPA state, one glance
├── tg_owt/          branch tgowt_ubuntu     → libtgowt-dev
├── tde2e/           branch tde2e_ubuntu     → libtde2e-dev
├── rnnoise/         branch rnnoise_ubuntu   → librnnoise-dev
└── tdesktop/        branch tdesktop_ubuntu  → telegram-desktop
```

Each branch is the upstream tree at the exact commit tdesktop pins, plus `debian/`,
`Containerfile`, `publish.sh`, `inside-container.sh` and `PACKAGING.md` — the same shape as
`titan-server` and `qca-bt-bridge`. All are **native** packages: the tree *is* the source, so
there is no orig tarball, no repack and no quilt. Any Ubuntu fix is an ordinary commit.

Carried over from the existing scripts: the temp-GnuPG-copy trick (strip `S.*`/`*.lock`), the
Containerfile-sha256 image label for rebuild detection, `--test-build` via `apt-get build-dep`
against a cached `apt-archives` volume, sha256 + signature verification of the
`.dsc`/`.changes`, `lintian` before upload, artifacts kept under `build-packages/`.

To follow an upstream bump: rebase the branch onto the newly pinned commit, add a changelog
entry, re-run. `status.sh` reports drift by checking the pin is still an ancestor of HEAD.

Version scheme: `0~git<date>.<short-sha>+ppa1~resolute1` — no hyphens (a native package takes
no Debian revision), and it sorts below any future official package of the same name.

`.cache/apt-archives/partial` in each clone is created by root inside the container, so
clearing a clone's cache needs `podman unshare rm -rf`.

## 4. Work order

**Step 1 — `libtgowt`, resolute amd64+arm64. ✅ published, all three arches built.**
`tg_owt` branch `tgowt_ubuntu`, native package, version
`0~git20260409.89df288+ppa1~resolute1` — upstream commit `89df288`, exactly the revision
tdesktop 7.0.7 pins. Source package signed and verified, lintian clean, binary build succeeds
on Ubuntu 26.04 producing a 29.5 MB `libtg_owt.a` with RNNoise included.

Layout diffed against the Debian-derived build: identical except the 27 libyuv + 2 RNNoise
headers Debian strips, and `changelog.gz` vs `changelog.Debian.gz` (native vs quilt).

**Step 1c — `rnnoise`. ✅ uploaded, building.**
`desktop-app/rnnoise` @ `d8ea2b0`, branch `rnnoise_ubuntu`. Required because with no prebuilt
libs directory `DESKTOP_APP_USE_PACKAGED` is forced ON
(`cmake_dependent_option(… OFF libs_loc_exists ON)`), and of the 22 externals in that mode
`rnnoise` is the only one that is `REQUIRED` with no bundled fallback — Ubuntu has no rnnoise
at all. Linked via `Telegram/cmake/lib_tgcalls.cmake:215`. The fork prefixes its internal
symbols so it can link alongside the copy inside tg_owt. Upstream installs no pkg-config file
while tdesktop looks it up with `pkg_check_modules`, so `debian/rules` generates `rnnoise.pc`.

**Step 1b — `tde2e`. ✅ uploaded, all three arches built.**
Telegram Desktop 7.x links `tde2e` unconditionally on Linux
(`Telegram/CMakeLists.txt:38,67`; `cmake/external/tde2e` does
`find_package(tde2e REQUIRED)`). It is in no distribution — plausibly the real reason Debian
is still on 5.7.2. Built from `tdlib/td` @ `51743df` with `TD_E2E_ONLY=ON`; exports
`tde2e::tde2e` and installs `td/e2e/e2e_api.h`, matching tdesktop's expectations exactly.

Near miss: `cmake/external/ton` expects a prebuilt TON blockchain library, but nothing links
`external_ton` in 7.0.7 — declared and inert. Had it been live, tonlib would need packaging too.

**Step 2 — `telegram-desktop` 7.0.7.** The actual job:
1. `mk-origtargz` the upstream `tdesktop-7.0.7-full.tar.gz` (77.6 MB) through
   `d/copyright`'s `Files-Excluded:` → `telegram-desktop_7.0.7+ds.orig.tar.xz`.
   The exclusion list needs updating: `dispatch`, `jemalloc`, `libtgvoip` are gone from
   upstream; `MicroTeX` and `TooManyCooks` are new and must **stay** vendored (unpackaged
   anywhere). `libcbor`, `libfido2`, `cmark-gfm` can be excluded and taken from Ubuntu
   (`libcbor-dev`, `libfido2-dev`, `libcmark-gfm-dev` all present — upstream added
   "Support packaged fido2" two commits before v7.0.7).
2. Triage Debian's 24 patches against 7.0.7. Expect the compat ones
   (`Fix-build-with-Qt-6.9`, `Compatibility-with-FFmpeg-8`, `1005`/`1006` missing includes,
   `Include-minizip-dir`, `Revert-Workaround-cmake-bug-25222`) to be obsolete; carry and
   rework the policy ones (`System-wide-cppgir`, `Skip-CLD3`, `Packed-resources`,
   `Really-disable-crash-reports`, `No-random-popups`, `XdgDesktopPortal`,
   `Generate-libprisma-grammars`, `Exclude-IV-resources`, `Disable-register-custom-scheme`).
3. `d/control`: add the new deps, keep the rest.
4. `d/rules`: swap api_id to `611335`. The Ubuntu LTO-off branch is already there.
5. `--test-build` locally on amd64 until it compiles, then upload. ~1 h per iteration.

## 5. Remaining choices (not blocking)

1. `amd64v3` — leave on (third build + quota) or turn off.
2. dbgsym — keep for debuggability or disable to protect the 8 GiB quota.
3. `stonking 26.10` — add later once resolute is green.
