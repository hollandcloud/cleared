#!/usr/bin/env bash
# Installs a pre-commit hook that runs the secret scan.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
cat > "$root/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/Scripts/scan-secrets.sh"
HOOK
chmod +x "$root/.git/hooks/pre-commit"
echo "✓ pre-commit hook installed"
