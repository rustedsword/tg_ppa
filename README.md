# tg_ppa

Ubuntu 26.04 (resolute) and 26.10 (stonking) packaging of **Telegram Desktop** and the four
libraries it needs that no distribution ships, for **amd64 and arm64**, published to
[ppa:lightofmysoul/tg](https://launchpad.net/~lightofmysoul/+archive/ubuntu/tg).

Upstream provides no official arm64 build, and Ubuntu removed `telegram-desktop` from the
archive in January 2023 in favour of the snap. Debian still maintains a package, but it is
pinned to upstream 5.7.2 (November 2024) — Telegram Desktop 7.x needs `tde2e` and, since
7.2.7, `tlottie`, and since 7.3.0 `wallet-engine`, none of which is in any distribution.

`ANALYSIS.md` records how this was scoped and why each decision was made.

## Layout

Each submodule is an upstream repository forked to `rustedsword`, checked out at the exact
commit Telegram Desktop pins, with a single packaging commit on top. The exception is
`tdesktop_rust/`: Telegram Desktop links its Rust libraries as one archive whose crate its
build recipes generate, so that repository is the generated crate with `tlottie` and
`wallet-engine` as submodules at their pins.

| path | fork | branch | produces |
|---|---|---|---|
| `tg_owt/` | `rustedsword/tg_owt` | `tgowt_ubuntu` | `libtgowt-dev` |
| `tde2e/` | `rustedsword/td` | `tde2e_ubuntu` | `libtde2e-dev` |
| `rnnoise/` | `rustedsword/rnnoise` | `rnnoise_ubuntu` | `librnnoise-dev` |
| `tdesktop_rust/` | `rustedsword/tdesktop_rust` | `tdesktop_rust_ubuntu` | `libtdesktop-rust-dev` |
| `tdesktop/` | `rustedsword/tdesktop` | `tdesktop_ubuntu` | `telegram-desktop` |

All five are **native** Debian packages: the checked-out tree *is* the source, so there is no
orig tarball, no `+ds` repack and no quilt patch stack. An Ubuntu-specific fix is an ordinary
commit on the branch.

## Cloning

```
git clone git@github.com:rustedsword/tg_ppa.git
cd tg_ppa
git submodule update --init                      # the five packaging trees
```

Do **not** use `--recursive` unless you mean it: `tdesktop` has 36 submodules of its own and
pulls a couple of GB. Initialise those only when building it:

```
git -C tdesktop submodule update --init --recursive
git -C tg_owt   submodule update --init src/third_party/libyuv src/third_party/crc32c/src
GIT_LFS_SKIP_SMUDGE=1 git -C tdesktop_rust submodule update --init
```

`tde2e` and `rnnoise` have no submodules.

## Building and publishing

Each submodule carries its own `publish.sh`, `inside-container.sh` and `Containerfile`. All
Debian work happens inside an Ubuntu podman container of the series being built, so the host
can be anything — these were developed on Gentoo.

```
cd tg_owt
./publish.sh --test-build --no-upload    # validate locally
./publish.sh                             # sign and upload; Launchpad builds the binaries
./publish.sh --help
```

`publish.sh` builds and uploads every series in its `SERIES` list, resolute and stonking.
`debian/changelog` always targets resolute; `inside-container.sh` retargets a copy of it for
stonking, so `…+ppa1~resolute1` goes to stonking as `…+ppa1~stonking1`. `--series NAME`
builds one series only. To add a series, add it to `SERIES` in all five `publish.sh`.

**Publish order matters.** Upload the libraries first — `libtgowt`, `tde2e`, `rnnoise`,
`tdesktop-rust`, whichever changed — and wait until their builds are *published* on the PPA
before uploading `telegram-desktop`. Uploaded together, `telegram-desktop` fails into
*Dependency wait*, and Launchpad only retries that queue about once an hour.

See each submodule's `PACKAGING.md` for what is specific to it.

## Status

```
./status.sh
```

Reports the commit each library is pinned at by `tdesktop/Telegram/build/prepare/prepare.py`,
whether our branch still contains that commit, and what the PPA currently holds.

## Following a new Telegram Desktop release

1. `git -C tdesktop fetch origin --tags` and rebase `tdesktop_ubuntu` onto the new tag.
2. `./status.sh` — any library whose pin moved shows `DRIFT`.
3. For each drifted library, rebase its single packaging commit onto the newly pinned commit:
   ```
   git rebase --onto <new-pin> <old-pin> <branch>
   ```
   then `dch -v 0~git<date>.<short-sha>+ppa1~resolute1 --distribution resolute "..."`.
   `tdesktop_rust` has no upstream to rebase onto: check its submodules out at the new pins
   and re-vendor — see its `PACKAGING.md`.
4. `./publish.sh --test-build` each changed package, then publish: the libraries first, and
   `telegram-desktop` only once their builds are published.
5. Update the submodule pointers here and commit.

Keeping exactly one packaging commit per branch is what makes step 3 a one-liner. Squash if a
change adds more.

## Version scheme

`0~git<date>.<short-sha>+ppa1~resolute1`

No hyphens — a native package takes no Debian revision. The leading `0~` sorts below any
future official package of the same name, so a real Ubuntu or Debian package would supersede
ours cleanly. `~resolute1` sorts below `~stonking1`, so upgrading Ubuntu upgrades the
packages.

## Prerequisites

- `podman`, `git`, `gpg`
- an OpenPGP key registered on Launchpad; the fingerprint is at the top of each `publish.sh`
- the key must have **no passphrase**, or `debuild` hangs waiting on pinentry inside the
  container

Note that `.cache/apt-archives/partial` inside each submodule is created by root in the
container; clearing a cache needs `podman unshare rm -rf`.
