#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/config/addons_state"
LOCAL_DST="/config/addons_local"
TIMESTAMP="$(date -Iseconds)"
HOSTNAME_SHORT="$(hostname -s || echo ha)"
GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_REMOTE="${GIT_REMOTE:-origin}"

log(){ echo "[export_addons] $*"; }

log "start ${TIMESTAMP}"

# ---------- 0) Forbered mapper ----------
mkdir -p "${STATE_DIR}" "${LOCAL_DST}"

# ---------- 1) Kopi av lokale add-ons ----------
if [ -d /addons/local ]; then
  rsync -a --delete /addons/local/ "${LOCAL_DST}/"
else
  log "/addons/local finnes ikke (ingen lokale add-ons?)"
fi

# ---------- 2) Hent add-ons-listen ----------
ADDONS_JSON="$(ha addons list --raw-json 2>/dev/null || true)"
if [ -z "${ADDONS_JSON}" ]; then
  log "ha CLI ga ingen data. Avslutter uten Git-commit."
  exit 0
fi

# Dump per‑addon info
echo "$ADDONS_JSON" \
| jq -r '.. | objects | .slug? // empty' \
| sort -u \
| while read -r SLUG; do
  [ -z "$SLUG" ] && continue
  log "dumpler ${SLUG}"
  ha addons info "$SLUG" --raw-json > "${STATE_DIR}/${SLUG}.info.json" || true
done

# ---------- 3) Lag indeks ----------
jq -n --arg t "${TIMESTAMP}" \
      --argjson add "$(echo "${ADDONS_JSON}" | jq '.data')" \
      '{timestamp:$t, addons:$add}' \
      > "${STATE_DIR}/_index.json"

# ---------- 4) Git: init/konfig ved behov ----------
cd /config

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "initierer git-repo i /config"
  git init
  git branch -M "${GIT_BRANCH}"
fi

# Sikre identitet (om ikke satt globalt)
git config --get user.name  >/dev/null || git config user.name  "HA ${HOSTNAME_SHORT}"
git config --get user.email >/dev/null || git config user.email "ha@${HOSTNAME_SHORT}.local"

# Sikre .gitignore
if [ ! -f .gitignore ]; then
  log "oppretter .gitignore"
  cat > .gitignore <<'EOF'
.storage/
home-assistant_v2.db*
*.log
*.db-shm
*.db-wal
.cloud/
deps/
media/
tmp/
tts/
custom_components/**/__pycache__/
**/__pycache__/
addons/
!addons/local/
backup/
secrets.yaml
*.key
*.pem
uploads/
.DS_Store
.vscode/
.idea/
EOF
fi

# ---------- 5) Stage, commit hvis endringer ----------
git add -A .gitignore || true

if [ -n "$(git status --porcelain)" ]; then
  COMMIT_MSG="addons snapshot ${TIMESTAMP} (${HOSTNAME_SHORT})"
  log "commit: ${COMMIT_MSG}"
  git commit -m "${COMMIT_MSG}"
else
  log "ingen endringer – hopper over commit"
fi

# ---------- 6) Push (hvis remote er satt) ----------
if git remote get-url "${GIT_REMOTE}" >/dev/null 2>&1; then
  # sørg for at branch finnes remote
  if ! git rev-parse --verify "${GIT_BRANCH}" >/dev/null 2>&1; then
    # ny branch – inget å gjøre spesielt; push vil opprette den
    :
  fi
  log "pusher til ${GIT_REMOTE}/${GIT_BRANCH}"
  # første gang kan -u være nyttig
  git push -u "${GIT_REMOTE}" "${GIT_BRANCH}" || {
    log "push feilet – sjekk deploy key / nett"
    exit 1
  }
else
  log "ingen git remote konfigurert – hopper over push (kjør: git remote add origin git@github.com:<user>/<repo>.git)"
fi

log "ferdig"
