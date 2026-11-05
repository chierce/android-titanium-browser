#!/usr/bin/env bash
# One-shot activation of the fork build workflow.
# Prerequisite: the `gh` token needs the `workflow` OAuth scope, because GitHub
# refuses any push that creates or updates files under .github/workflows/ for
# tokens without it. Fix that once, interactively, in a real terminal:
#
#   gh auth refresh -s workflow      # approve in the browser it opens
#
# Then this script needs no further input.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if ! gh auth status 2>&1 | grep -q "workflow"; then
  echo "token still lacks the workflow scope. run: gh auth refresh -s workflow" >&2
  exit 1
fi

mkdir -p .github/workflows
git mv ci/build-fork.yml .github/workflows/build-fork.yml 2>/dev/null || mv ci/build-fork.yml .github/workflows/build-fork.yml

git add .github/workflows/build-fork.yml
git -c user.name="chierce" -c user.email="chierce@users.noreply.github.com" \
  commit -m "ci: activate fork build workflow"
git push

echo
echo "workflow active. trigger a run with:"
echo "  gh workflow run 'Build (fork)' -f runner=self-hosted -f abi=arm64-v8a"
echo
echo "note: ubuntu-latest will stop at the preflight job on purpose - 14 GB disk"
echo "cannot hold a Chromium Android checkout. use a self-hosted runner."