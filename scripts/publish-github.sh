#!/bin/bash
# One-time publish to GitHub. Requires: brew install gh && gh auth login
set -euo pipefail
cd "$(dirname "$0")/.."

if ! gh auth status &>/dev/null; then
  echo "→ Log in to GitHub first:"
  gh auth login -h github.com -p https -w
fi

if git remote get-url origin &>/dev/null; then
  echo "→ Remote already set. Pushing…"
  git push -u origin main
else
  echo "→ Creating public repo and pushing…"
  gh repo create accentum \
    --public \
    --description "macOS menu bar controller for Sennheiser Accentum headphones (ANC, transparency, EQ)" \
    --source=. \
    --remote=origin \
    --push
fi

USER=$(gh api user -q .login)
echo ""
echo "✓ Published: https://github.com/${USER}/accentum"
