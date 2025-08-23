#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/config/addons_state"
LOCAL_DST="/config/addons_local"
TIMESTAMP="$(date -Iseconds)"

echo "[export_addons] start ${TIMESTAMP}"

# 1) Kopi av lokale add-ons (kildekode) for Git
#    -> /addons/local (host) til /config/addons_local
if [ -d /addons/local ]; then
  rsync -a --delete /addons/local/ "${LOCAL_DST}/"
else
  echo "[export_addons] /addons/local finnes ikke (ingen lokale add-ons?)"
fi

# 2) Liste ut alle add-ons (slugs)
# Merk: --raw-json gjør det lett å parse med jq
ADDONS_JSON="$(ha addons list --raw-json 2>/dev/null || true)"
if [ -z "${ADDONS_JSON}" ]; then
  echo "[export_addons] ha CLI ga ingen data. Er HA CLI tilgjengelig i dette skallet?"
  exit 0
fi

# Plukk alle slug-felt i hele strukturen, fjern duplikater og tomme
echo "$ADDONS_JSON" \
| jq -r '.. | objects | .slug? // empty' \
| sort -u \
| while read -r SLUG; do
  [ -z "$SLUG" ] && continue
  echo "[export_addons] dumper $SLUG"
  mkdir -p "${STATE_DIR:-/config/addon_state}"
  ha addons info "$SLUG" --raw-json > "${STATE_DIR:-/config/addon_state}/${SLUG}.info.json" || true
done

# 3) Lag en indeks-fil med tidspunkt
jq -n --arg t "${TIMESTAMP}" \
      --argjson add "$(echo "${ADDONS_JSON}" | jq '.data')" \
      '{timestamp:$t, addons:$add}' \
      > "${STATE_DIR}/_index.json"

echo "[export_addons] ferdig"
