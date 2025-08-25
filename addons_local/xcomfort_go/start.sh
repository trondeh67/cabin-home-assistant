#!/bin/sh
set -eu

OPTIONS=/data/options.json

# Vent til options.json finnes og er en fil (ikke katalog)
for i in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$OPTIONS" ] && break
  echo "[xcomfort] venter på $OPTIONS ..." >&2
  sleep 1
done

# Liten hjelpefunksjon: les nøkkel, returner tom streng ved feil
getoptjson() {
  key="$1"
  jq -er "$key" "$OPTIONS" 2>/dev/null || echo ""
}

MQTT_URL="$(getoptjson '.mqtt_url')"
LOG_LEVEL="$(getoptjson '.log_level')"
EXTRA_ARGS="$(getoptjson '.extra_args // ""')"
DPFILE="$(getoptjson '.datapoint_file // ""')"

ARGS="--hadiscovery -s ${MQTT_URL}"
[ "$LOG_LEVEL" = "debug" ] && ARGS="$ARGS --verbose"

if [ -n "$DPFILE" ] && [ -f "$DPFILE" ]; then
  echo "[xcomfort] bruker DPL-fil: $DPFILE"
  ARGS="-f $DPFILE $ARGS"
else
  echo "[xcomfort] ingen DPL-fil funnet – prøver EEPROM (-e)"
  ARGS="-e $ARGS"
fi

echo "[xcomfort] starter: /usr/local/bin/xcomfortd-go $ARGS $EXTRA_ARGS"
exec /usr/local/bin/xcomfortd-go $ARGS $EXTRA_ARGS
