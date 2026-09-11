#!/usr/bin/env sh
set -eu
target="${CODEX_HOME:-$HOME/.codex}/skills/carer-record"
mkdir -p "$target"
cp skills/carer-record/SKILL.md "$target/SKILL.md"
printf '%s\n' "Installed Carer Record skill in $target"
