#!/usr/bin/env bash
set -euo pipefail
ADDON_DIR="${1:-/addons/local/xcomfort_go2}"
fail=0

say() { echo "[$(date +%H:%M:%S)] $*"; }

if [ ! -d "$ADDON_DIR" ]; then echo "Finner ikke $ADDON_DIR"; exit 2; fi

say "Sjekker filer i $ADDON_DIR …"
ls -la "$ADDON_DIR" || true

# 1) Kun config.json (ikke YAML)
if [ -f "$ADDON_DIR/config.yaml" ]; then
  echo "❌ config.yaml finnes – HA bruker kun config.json. Slett den."
  fail=1
else
  echo "✅ Ingen config.yaml funnet."
fi
if [ ! -f "$ADDON_DIR/config.json" ]; then
  echo "❌ Mangler config.json."
  fail=1
else
  echo "✅ config.json finnes."
  if ! jq . "$ADDON_DIR/config.json" >/dev/null 2>&1; then
    echo "❌ Ugyldig JSON i config.json."
    fail=1
  fi
fi

# 2) Slug/ID
if [ -f "$ADDON_DIR/config.json" ]; then
  slug=$(jq -r '.slug' "$ADDON_DIR/config.json")
  if [ -z "$slug" ] || [ "$slug" = "null" ]; then
    echo "❌ .slug mangler i config.json"
    fail=1
  else
    echo "✅ slug: $slug  (Add-on ID blir: local_$slug)"
  fi
fi

# 3) Riktig s6-service
RUN="$ADDON_DIR/rootfs/etc/services.d"
if [ ! -d "$RUN" ]; then
  echo "❌ Mangler rootfs/etc/services.d/*/run"
  fail=1
else
  svc=$(find "$RUN" -maxdepth 2 -type f -name run | head -n1 || true)
  if [ -z "$svc" ]; then
    echo "❌ Fant ingen service 'run' under $RUN"
    fail=1
  else
    echo "✅ Fant service run: $svc"
    if ! head -n1 "$svc" | grep -q "/command/with-contenv"; then
      echo "❌ Shebang bør være: #!/command/with-contenv bashio"
      fail=1
    else
      echo "✅ Shebang OK."
    fi
    if ! grep -q "^exec " "$svc"; then
      echo "❌ 'run' bør avslutte med 'exec <din-binær> …'"
      fail=1
    else
      echo "✅ 'run' bruker exec."
    fi
    if grep -E 's6-overlay-suexec|/init' -n "$svc"; then
      echo "❌ 'run' refererer til s6-overlay-suexec eller /init – fjern dette."
      fail=1
    else
      echo "✅ Ingen kall til /init eller s6-overlay-suexec i run."
    fi
    if [ ! -x "$svc" ]; then
      echo "❌ 'run' er ikke kjørbar – kjør: chmod +x '$svc'"
      fail=1
    fi
  fi
fi

# 4) Dockerfile
DF="$ADDON_DIR/Dockerfile"
if [ ! -f "$DF" ]; then
  echo "❌ Mangler Dockerfile."
  fail=1
else
  echo "✅ Dockerfile funnet."
  if grep -E 'ENTRYPOINT|CMD' "$DF"; then
    echo "❌ Dockerfile setter ENTRYPOINT/CMD – fjern (HA base starter /init)."
    fail=1
  else
    echo "✅ Ingen ENTRYPOINT/CMD i Dockerfile."
  fi
  if grep -E 's6-overlay|/init' "$DF"; then
    echo "❌ Dockerfile refererer til s6-overlay eller /init – fjern."
    fail=1
  else
    echo "✅ Ingen manuell s6-overlay i Dockerfile."
  fi
fi

# 5) Options-samsvar
if [ -f "$ADDON_DIR/config.json" ]; then
  echo "— Verifiser at nøkler i schema og options matcher bruken i run —"
  schema=$(jq -r '.schema|keys[]?' "$ADDON_DIR/config.json" 2>/dev/null || true)
  opts=$(jq -r '.options|keys[]?' "$ADDON_DIR/config.json" 2>/dev/null || true)
  echo "Schema: $schema"
  echo "Options: $opts"
fi

# 6) Finn utilsiktede /init-kall
if grep -R -nE 's6-overlay-suexec|/init' "$ADDON_DIR" | grep -v 'rootfs/etc/cont-init.d' ; then
  echo "❌ Fant referanser til /init/s6-overlay i repoet – bør bort."
  fail=1
else
  echo "✅ Ingen utilsiktede /init/suexec-referanser."
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "✅ Alt ser bra ut på stru

