#!/bin/bash
#
# uv_setup.sh <venv_dir> <toml_dir> <uv_version> [<group> ...]
#
# Ensures uv is installed at $uv_version, runs `uv lock` to refresh the
# lockfile against $toml_dir/pyproject.toml (no-op when already in
# sync), then runs `uv sync --frozen` to materialize the venv at
# $venv_dir/.venv. $toml_dir is the project root containing the
# pyproject.toml + uv.lock pair that uv resolves against — under
# pyro's project-root model this is the user's project, seeded
# from the bundled spec on first init.
#
# When zero group args are supplied, runs:
#   uv sync --frozen --all-groups
# When one or more group args are supplied, runs:
#   uv sync --frozen --inexact --group <g1> --group <g2> ...
# `--inexact` keeps packages from previously installed groups in place,
# so sibling fyr-packages can each install their own group additively
# without removing each other's deps.

set -euo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: $0 <venv_dir> <toml_dir> <uv_version> [<group> ...]" >&2
  exit 2
fi

VENV_DIR="$1"
TOML_DIR="$2"
UV_VERSION="$3"
shift 3
DEP_GROUPS=("$@")

if [ -z "$VENV_DIR" ] || [ -z "$TOML_DIR" ] || [ -z "$UV_VERSION" ]; then
  echo "venv_dir, toml_dir, and uv_version must all be non-empty" >&2
  exit 2
fi

if [ ! -d "$TOML_DIR" ]; then
  echo "toml_dir '$TOML_DIR' does not exist" >&2
  exit 2
fi

# Force uv's installer to use $HOME/.local/bin regardless of how
# CARGO_HOME / XDG vars are configured (on shared-filesystem setups like
# AWS ParallelCluster, CARGO_HOME can point at an ephemeral instance-
# scoped path the installer would otherwise use, leaving uv off PATH).
install_uv() {
  local version="$1"
  (
    unset CARGO_HOME
    export XDG_BIN_HOME="$HOME/.local/bin"
    mkdir -p "$XDG_BIN_HOME"
    curl --proto '=https' --tlsv1.2 -LsSf \
      "https://github.com/astral-sh/uv/releases/download/$version/uv-installer.sh" \
      | sh
  )
  export PATH="$HOME/.local/bin:$PATH"
  if ! command -v uv >/dev/null 2>&1; then
    echo "uv not found on PATH after install (expected at $HOME/.local/bin/uv)" >&2
    exit 1
  fi
}

# Make an already-installed ~/.local/bin uv visible without mutating dotfiles.
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "uv not installed; installing $UV_VERSION..."
  install_uv "$UV_VERSION"
else
  installed_ver="$(uv --version 2>/dev/null | awk '{print $2}')"
  if [[ "$installed_ver" != "$UV_VERSION" ]]; then
    echo "uv $installed_ver != required $UV_VERSION; installing $UV_VERSION..."
    install_uv "$UV_VERSION"
  else
    echo "Using existing uv $installed_ver."
  fi
fi

# --frozen: fail loudly if pyproject.toml and uv.lock drift.
# --all-groups (no DEP_GROUPS): install every declared dependency group.
# --inexact + --group X (with DEP_GROUPS): additively install named groups,
#   leaving extraneous packages from previous syncs in place.
export UV_PROJECT_ENVIRONMENT="$VENV_DIR/.venv"

# Refresh the lock to match the toml. uv lock is a no-op when the lock
# is already up-to-date; if the user edited pyproject.toml or pyro
# (or a sibling wrapper) just spliced in a new group, this regenerates.
uv lock --project "$TOML_DIR"

if [ ${#DEP_GROUPS[@]} -eq 0 ]; then
  uv sync \
    --project "$TOML_DIR" \
    --frozen \
    --all-groups
else
  GROUP_ARGS=()
  for g in "${DEP_GROUPS[@]}"; do
    GROUP_ARGS+=(--group "$g")
  done
  uv sync \
    --project "$TOML_DIR" \
    --frozen \
    --inexact \
    "${GROUP_ARGS[@]}"
fi

echo "Python environment ready at $UV_PROJECT_ENVIRONMENT"
