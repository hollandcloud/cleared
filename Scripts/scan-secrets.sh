#!/usr/bin/env bash
# Refuses to let a credential reach the history of a public repository.
# Run by `make scan`, and by the pre-commit hook in Scripts/install-hooks.sh.
set -uo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
status=0

# Token shapes GitHub actually issues, plus generic private-key headers.
patterns=(
  'gh[pousr]_[A-Za-z0-9]{36,}'
  'github_pat_[A-Za-z0-9_]{22,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'AKIA[0-9A-Z]{16}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
)

files=$(git ls-files 2>/dev/null || find . -type f -not -path './.git/*')

for pattern in "${patterns[@]}"; do
  if hits=$(printf '%s\n' "$files" | xargs -r grep -InE -e "$pattern" 2>/dev/null); then
    if [ -n "$hits" ]; then
      echo "${RED}✖ Possible credential matching /${pattern}/:${RESET}"
      echo "$hits"
      status=1
    fi
  fi
done

if [ "$status" -eq 0 ]; then
  echo "${GREEN}✓ No credentials found in tracked files.${RESET}"
fi
exit "$status"
