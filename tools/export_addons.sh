#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/config/addons_state"
LOCAL_DST="/config/addons_local"
TIMESTAMP="$(date -Iseconds)"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || echo ha)"
GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_REMOTE="${GIT_REMOTE:-origin}"

log(){ echo "[export_addons] $*"; }
die(){ echo "[export_addons][ERROR] $*" >&2; exit 1; }

require_cmd(){ command -v "$1" >/dev/null 2>&1 || die "Manglende kommando: $1"; }

umask 022

# ---------- 0) Preflight ----------
require_cmd jq
require_cmd rsync
require_cmd git
# 'ha' kan mangle i noen miljøer – ikke drep skriptet hvis den mangler
HAS_HA_CLI=1
command -v ha >/dev/null 2>&1 || HAS_HA_CLI=0

log "start ${TIMESTAMP}"

# ---------- 1) Forbered mapper ----------
mkdir -p "${STATE_DIR}" "${LOCAL_DST}"

# ---------- 2) Kopi av lokale add-ons ----------
if [ -d /addons/local ]; then
  # -a (arkiv), -v (verbose), --delete (speil), --inplace=false (atomic temp-fil)
  rsync -av --delete /addons/local/ "${LOCAL_DST}/"
else
  log "/addons/local finnes ikke (ingen lokale add-ons?)"
fi

# ---------- 3) Hent add-ons-listen ----------
ADDONS_JSON=""
if [ "$HAS_HA_CLI" -eq 1 ]; then
  # Bruk midlertidig fil for å unngå delvise writes
  tmpjson="$(mktemp)"
  if ha addons list --raw-json > "$tmpjson" 2>/dev/null; then
    ADDONS_JSON="$(cat "$tmpjson")"
  fi
  rm -f "$tmpjson"
fi

if [ -z "${ADDONS_JSON}" ]; then
  log "ha CLI ga ingen data (eller finnes ikke). Hopper over add-on dump, fortsetter med Git."
else
  # Dump per-addon info (fail ikke på enkeltslug)
  echo "$ADDONS_JSON" \
  | jq -r '.. | objects | .slug? // empty' \
  | sort -u \
  | while read -r SLUG; do
      [ -z "$SLUG" ] && continue
      log "dumpler ${SLUG}"
      if ! ha addons info "$SLUG" --raw-json > "${STATE_DIR}/${SLUG}.info.json" 2>/dev/null; then
        log "advarsel: kunne ikke hente info for ${SLUG}"
      fi
    done

  # Lag indeks atomisk
  tmpindex="$(mktemp)"
  jq -n --arg t "${TIMESTAMP}" \
        --argjson add "$(echo "${ADDONS_JSON}" | jq '.data')" \
        '{timestamp:$t, addons:$add}' > "$tmpindex"
  mv -f "$tmpindex" "${STATE_DIR}/_index.json"
fi

# ---------- 4) Git: init/konfig ved behov ----------
cd /config

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "initierer git-repo i /config"
  git init
  git checkout -b "${GIT_BRANCH}" >/dev/null 2>&1 || git branch -M "${GIT_BRANCH}"
fi

# Identitet om ikke satt globalt
git config --get user.name  >/dev/null || git config user.name  "HA ${HOSTNAME_SHORT}"
git config --get user.email >/dev/null || git config user.email "ha@${HOSTNAME_SHORT}.local"

# ---------- 5) Sikre .gitignore (append-safe) ----------
ensure_gitignore() {
  local gi=".gitignore"
  if [ ! -f "$gi" ]; then
    log "oppretter .gitignore"
    cat > "$gi" <<'EOF'
# Home Assistant runtime
.storage/
home-assistant_v2.db*
home-assistant.sqlite*
home-assistant.log*
.cloud/
deps/
tts/
media/
tmp/
.custom_components/**/__pycache__/
**/__pycache__/

# Backups / secrets
backups/
backup/
secrets.yaml
*.key
*.pem

# HACS / bygde artefakter (kan reproduseres)
www/community/
www/*.map

# Zigbee2MQTT volatile
zigbee2mqtt/database.db
zigbee2mqtt/state.json
zigbee2mqtt/log/
zigbee2mqtt/coordinator_backup.json

# Add-on cache/state
addons/
!addons/local/        # behold lokale add-ons
# addons_state/*.json

# IDE / OS
.vscode/
.idea/
.DS_Store
Thumbs.db
*.tmp
*.swp
EOF
  else
    # Sikre at sentrale mønstre finnes (idempotent append)
    add_ignore() { grep -qxF "$1" "$gi" || echo "$1" >> "$gi"; }
    add_ignore ".storage/"
    add_ignore "home-assistant_v2.db*"
    add_ignore "home-assistant.log*"
    add_ignore "www/community/"
    add_ignore "zigbee2mqtt/database.db"
    add_ignore "zigbee2mqtt/state.json"
    add_ignore "zigbee2mqtt/log/"
    add_ignore "addons/"
    add_ignore "!addons/local/"
    add_ignore "addons_state/*.json"
  fi
}
ensure_gitignore

# ---------- 6) Sync mot remote (hvis konfigurert) ----------
if git remote get-url "${GIT_REMOTE}" >/dev/null 2>&1; then
  log "henter fra ${GIT_REMOTE}"
  git fetch --all -q || log "advarsel: fetch feilet"
  # Rebase for å unngå unødige merge-commits
  if git rev-parse --verify "${GIT_BRANCH}" >/dev/null 2>&1; then
    git -c pull.rebase=true -c rebase.autoStash=true pull -q "${GIT_REMOTE}" "${GIT_BRANCH}" || \
      log "advarsel: pull --rebase feilet (fortsetter lokalt)"
  fi
else
  log "ingen git remote konfigurert – hopper over fetch/pull (tips: git remote add ${GIT_REMOTE} git@github.com:<user>/<repo>.git)"
fi

# ---------- 7) Stage og commit ----------
# Stage ALT, .gitignore filtrerer støy
git add -A

# Commit kun hvis det faktisk er noe staged
if ! git diff --cached --quiet; then
  COMMIT_MSG="addons snapshot ${TIMESTAMP} (${HOSTNAME_SHORT})"
  log "commit: ${COMMIT_MSG}"
  git commit -m "${COMMIT_MSG}"
else
  log "ingen endringer – hopper over commit"
fi

# ---------- 8) Push (hvis remote er satt) ----------
if git remote get-url "${GIT_REMOTE}" >/dev/null 2>&1; then
  log "pusher til ${GIT_REMOTE}/${GIT_BRANCH}"
  # Første gang: sett upstream
  if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
    git push -u "${GIT_REMOTE}" "${GIT_BRANCH}" || { log "push feilet – sjekk deploy key / nett"; exit 1; }
  else
    git push "${GIT_REMOTE}" "${GIT_BRANCH}" || { log "push feilet – sjekk deploy key / nett"; exit 1; }
  fi
else
  log "ingen git remote konfigurert – hopper over push"
fi

log "ferdig"
