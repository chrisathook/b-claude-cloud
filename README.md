# b-claude-cloud

Setup script for a [Claude Code cloud environment](https://code.claude.com/docs/en/cloud-environments). It provisions the session VM (Ubuntu 24.04, x86_64) with:

| Tool | Version | Notes |
| --- | --- | --- |
| Node.js | 24 (pinned) | Installed in `/opt/node22` so it's the default `node` on the VM's PATH |
| pnpm, yarn | latest at build time | Reinstalled globally on Node 24 |
| Playwright | pinned | Chromium plus its system libraries |
| Python 3 | 3.14 line (pinned minor) | Installed with uv; linked as `python3` and `python` |
| ffmpeg | Ubuntu 24.04 package | |
| ImageMagick | Ubuntu 24.04 package | ImageMagick 6, so the command is `convert`, not `magick` |

## How it works

A cloud environment's setup script is a field in the environment's settings on claude.ai. It can't point at a file in a repo directly. So the environment holds a short **bootstrap** that downloads `setup.sh` from this repo, pinned to a commit, checks its SHA-256 hash, and runs it.

The setup script runs as root before Claude Code starts. If it finishes in under about five minutes, the resulting filesystem is snapshotted and reused by later sessions, so the installs don't repeat each time. The snapshot is rebuilt when the environment's setup script or allowed network hosts change, and roughly every seven days.

Because the bootstrap pins a commit, pushing to `main` changes nothing until the bootstrap is updated. Updating the bootstrap text is also what triggers a snapshot rebuild.

## Setting up an environment

1. Open [claude.ai/code](https://claude.ai/code), click the environment selector under the message box, and choose **New environment**. To edit an existing one, hover over it and click its settings icon. For an environment shared with your whole organization, an Owner uses the **Cloud environments** page in admin settings instead.

2. Set **Network access** to **Custom**, check **Also include default list of common package managers**, and add these domains for Playwright's browser downloads:

   ```
   cdn.playwright.dev
   playwright.download.prss.microsoft.com
   playwright.azureedge.net
   ```

3. Paste the bootstrap into the **Setup script** field, filling in the commit and hash from [Current release](#current-release):

   ```bash
   #!/bin/bash
   set -euo pipefail
   REV=<full commit SHA>
   curl -fsSL "https://raw.githubusercontent.com/chrisathook/b-claude-cloud/${REV}/setup.sh" -o /tmp/setup.sh
   echo "<sha256>  /tmp/setup.sh" | sha256sum -c -
   bash /tmp/setup.sh
   ```

4. Save, then start a session in the environment. The first session runs the full setup. Expand **Show details** on the setup step to see the versions the script installed.

## Current release

| Commit | SHA-256 of `setup.sh` |
| --- | --- |
| `<full commit SHA>` | `<sha256>` |

## Releasing a change

1. Edit `setup.sh`. Change versions by editing the pins at the top of the file; the comments there show how to look up the latest Node 24 and Playwright releases.
2. Commit and push.
3. Get the full commit SHA and the file's hash:

   ```bash
   git rev-parse HEAD
   shasum -a 256 setup.sh      # macOS
   sha256sum setup.sh          # Linux
   ```

4. Update [Current release](#current-release) in this README and commit it. The README commit doesn't change `setup.sh`, so the hash still matches.
5. Test first: create a second, personal environment with the new `REV` and hash, start a session, and confirm it boots and reports the right versions.
6. Update `REV` and the hash in the bootstrap of each environment that uses this script.

Always use the full 40-character commit SHA, never a branch name like `main`. A branch URL would run whatever was pushed last and fail the hash check after every push.

## Verifying a session

Ask Claude in a new session to run:

```bash
which node && node -v && python3 --version && ffmpeg -version | head -1 && convert -version | head -1 && playwright --version
```

`which node` should print `/opt/node22/bin/node` while `node -v` prints `v24.x`. The directory keeps Node 22's name so the VM's default PATH finds Node 24 without any PATH changes. The original Node 22 is kept at `/opt/node22.orig`.

## Troubleshooting

**The session doesn't start.** Expand **Show details** on the setup step. The script exits non-zero on any failure, and a non-zero exit stops the session from starting. Common causes:

- `sha256sum: WARNING: 1 computed checksum did NOT match` means the hash in the bootstrap doesn't match the file at `REV`.
- `ERROR: pin NODE_VERSION and PLAYWRIGHT_VERSION` means the pins at the top of `setup.sh` still hold placeholders.
- A failed Playwright download usually means a domain from step 2 of [Setting up an environment](#setting-up-an-environment) is missing from the allowlist.

**Sessions are slow to start every time.** The setup took longer than about five minutes, so no snapshot was cached. Check the timestamps in the setup log to find the slow step.

**Environment variables are empty in the setup script.** That's expected. Variables from the environment's **Environment variables** panel are only set once the session is running, not while the setup script runs. Don't put secrets in this script or this repo; it's public.

**Project dependencies** such as `pnpm install`, or a project-specific Playwright browser version, belong in a SessionStart hook in that project's `.claude/settings.json`, not in this script.
