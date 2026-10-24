#!/bin/bash
# Claude Code cloud environment setup
# Installs: ffmpeg, ImageMagick, Node 24 (as the default node), pnpm, yarn,
#           Playwright + Chromium, and a current Python 3 via uv.
#
# Runs as root on Ubuntu 24.04 (x86_64) before Claude Code launches.
# Keep total runtime under ~5 minutes so the environment snapshot gets cached.
#
# Required network access: Custom, with the default package-manager list included, plus:
#   cdn.playwright.dev
#   playwright.download.prss.microsoft.com
#   playwright.azureedge.net

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# Pinned versions — bump these deliberately, in a commit.
#   Latest Node 24:   curl -s https://nodejs.org/dist/index.json | jq -r '[.[]|select(.version|startswith("v24."))][0].version'
#   Latest Playwright: npm view playwright version
# ---------------------------------------------------------------------------
NODE_VERSION="v24.11.0"        # e.g. v24.11.0 — must be an exact release
PYTHON_VERSION="3.14"         # minor pin; uv picks the newest patch release
PLAYWRIGHT_VERSION="1.56.0"    # exact version, e.g. 1.56.0

NODE_DIR=/opt/node22          # Node 22's slot is on the default PATH; Node 24 goes here
PYTHON_DIR=/opt/python

log() { echo "[setup] $(date -u +%H:%M:%S) $*"; }

if [[ "$NODE_VERSION" == *X* || "$PLAYWRIGHT_VERSION" == *X* ]]; then
  echo "[setup] ERROR: pin NODE_VERSION and PLAYWRIGHT_VERSION before using this script" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Three independent installs in parallel: apt packages, Node, Python
# ---------------------------------------------------------------------------
install_apt() {
  log "apt: ffmpeg imagemagick"
  apt-get update -q
  apt-get install -y -q --no-install-recommends ffmpeg imagemagick
  log "apt: done"
}

install_node() {
  log "node: ${NODE_VERSION}"
  local tarball="node-${NODE_VERSION}-linux-x64.tar.xz"
  local tmp; tmp=$(mktemp -d)
  curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${tarball}" -o "${tmp}/${tarball}"
  curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt" -o "${tmp}/SHASUMS256.txt"
  (cd "$tmp" && grep " ${tarball}\$" SHASUMS256.txt | sha256sum -c -)

  # Move the preinstalled Node 22 aside (once) and put Node 24 in its place
  if [[ -d "$NODE_DIR" && ! -d "${NODE_DIR}.orig" ]]; then
    mv "$NODE_DIR" "${NODE_DIR}.orig"
  fi
  rm -rf "$NODE_DIR"
  mkdir -p "$NODE_DIR"
  tar -xJf "${tmp}/${tarball}" -C "$NODE_DIR" --strip-components=1
  rm -rf "$tmp"
  log "node: done"
}

install_python() {
  log "python: ${PYTHON_VERSION} via uv"
  UV_PYTHON_INSTALL_DIR="$PYTHON_DIR" uv python install "$PYTHON_VERSION"
  local py
  py=$(ls -d "${PYTHON_DIR}"/cpython-"${PYTHON_VERSION}".*-linux-x86_64-gnu 2>/dev/null | sort -V | tail -1)
  [[ -n "$py" ]] || { echo "[setup] ERROR: uv Python not found in ${PYTHON_DIR}" >&2; return 1; }
  ln -sf "${py}/bin/python3" /usr/local/bin/python3
  ln -sf "${py}/bin/python3" /usr/local/bin/python
  log "python: done"
}

install_apt    & APT_PID=$!
install_node   & NODE_PID=$!
install_python & PY_PID=$!

wait "$APT_PID"
wait "$NODE_PID"
wait "$PY_PID"

# ---------------------------------------------------------------------------
# 2. Global Node tools on Node 24 (the old Node 22 globals went with the move)
# ---------------------------------------------------------------------------
export PATH="${NODE_DIR}/bin:${PATH}"
log "npm globals: pnpm yarn playwright@${PLAYWRIGHT_VERSION}"
npm install -g --no-fund --no-audit pnpm yarn "playwright@${PLAYWRIGHT_VERSION}"

# ---------------------------------------------------------------------------
# 3. Playwright browser + its system libraries (uses apt, so runs after step 1)
# ---------------------------------------------------------------------------
log "playwright: chromium + deps"
playwright install --with-deps chromium

# ---------------------------------------------------------------------------
# 4. Report versions (shows up in the setup step's details)
# ---------------------------------------------------------------------------
log "installed versions:"
echo "  node        $(node -v)"
echo "  npm         $(npm -v)"
echo "  pnpm        $(pnpm -v)"
echo "  python3     $(python3 --version 2>&1)"
echo "  ffmpeg      $(ffmpeg -version | head -1)"
echo "  imagemagick $(convert -version | head -1)"
echo "  playwright  $(playwright --version)"

log "setup complete"
exit 0
