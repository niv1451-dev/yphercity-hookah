#!/usr/bin/env bash
# Runs every automated check that does not need a FiveM server.
# Requirements: lua5.4, luacheck, node (and optionally Playwright + Chromium for the UI test).
# Optional: NATIVES_DIR=/path/to/citizenfx/natives FIVEM_DECLS=/path/to/fivem/ext/native-decls
set -u
cd "$(dirname "$0")/.."
status=0

step() {
  local title="$1"; shift
  echo
  echo "════ $title"
  if "$@"; then echo "──── OK"; else echo "──── FAILED"; status=1; fi
}

skip() { echo; echo "════ $1"; echo "──── SKIPPED: $2"; }

step "Lint (luacheck)" luacheck . --formatter plain
step "Lua syntax (luac -p)" bash -c 'for f in $(find . -name "*.lua" -not -path "./tests/*"); do luac5.4 -p "$f" || exit 1; done'
step "JavaScript syntax (node --check)" bash -c 'node --check html/app.js && node --check html/locale.js && node --check tests/nui/mock.js'
step "Server + client logic (Lua, FiveM mock)" lua5.4 tests/lua/run.lua
step "Sample data for the UI preview" bash -c 'lua5.4 tests/lua/export_catalog.lua > tests/nui/mock-data.js'
step "Cross-file checks" node tests/static_checks.js

if node -e "require('playwright')" 2>/dev/null; then
  step "UI end-to-end (Chromium)" node tests/nui/nui.test.js "${SCREENSHOTS:-}"
else
  skip "UI end-to-end (Chromium)" "Playwright is not installed (npm i -D playwright && npx playwright install chromium)"
fi

if [ -n "${NATIVES_DIR:-}" ] && [ -n "${FIVEM_DECLS:-}" ]; then
  step "Natives exist / correct side / argument count" python3 tests/check_natives.py "$NATIVES_DIR" "$FIVEM_DECLS"
else
  skip "Natives check" "set NATIVES_DIR and FIVEM_DECLS (see tests/check_natives.py)"
fi

echo
if [ $status -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; fi
exit $status
