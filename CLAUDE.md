# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Home Assistant configuration repository for a Norwegian cabin called **Tjukktømmern**. It manages lighting (Eaton xComfort + Zigbee), climate (Daikin heat pump, Sensibo, Netatmo), security (Verisure alarm), outdoor frost protection (varmekabel), and cabin arrival/departure heating control.

## Validation & Maintenance Commands

```bash
# Validate xComfort local addon structure before deploying
bash validate_xcomfort_addon.sh

# Export addon state and push to git (runs as cron on the HA host)
bash tools/export_addons.sh
```

There is no build/lint/test pipeline — Home Assistant validates configuration at startup. The only way to verify YAML correctness is via the HA Developer Tools > YAML validation in the UI, or by restarting Home Assistant.

## Git Workflow

This repo is edited from two places: this machine and the HA host (`/config`). Always sync before editing:

```bash
git pull --rebase
# ... make changes ...
git add <files>
git commit -m "..."
git push
```

If push is rejected, run `git pull --rebase` first. Snapshot commits (`addons snapshot …`) in git log are automated from the HA cron job — ignore them.

## Architecture

### Configuration Layout

| File / Directory | Purpose |
|---|---|
| `configuration.yaml` | Main HA config: platform setup, HTTP, template sensors, package includes |
| `automations.yaml` | All automations (light triggers, alarm reactions, MQTT buttons) |
| `scripts.yaml` | Reusable scripts: all-lights-off with xComfort retries, scene restoration, cabin arrival/departure heating control |
| `scenes.yaml` | Lighting scenes per room (~1300 lines, Norwegian room names) |
| `packages/` | Self-contained feature packages loaded via `homeassistant.packages` |
| `lovelace/hytte/` | YAML-mode Lovelace dashboards (main: `tjukktommern.yaml`) |
| `addons_local/` | Local custom HA addons (xComfort bridge) |
| `xcomfort_datapoints.yaml` | Eaton xComfort device ID ↔ entity mapping |
| `zigbee2mqtt/` | Zigbee2MQTT broker config and device database |

### What Is NOT Tracked

HACS-managed components are excluded from git — they are updated automatically by HACS:
- `custom_components/hacs/`
- `custom_components/daikin_onecta/`
- `custom_components/google_assistant_sdk_custom/`

Also excluded: `.HA_VERSION`, `.cache/`, `.ha_run.lock`, databases, logs.

### Norwegian Room Names

Scenes and entities use Norwegian names. Key rooms:
- **Stue** — living room
- **Kjøkken** — kitchen
- **Spisestue** — dining room
- **Gang** — hallway
- **Vindfang** — entryway/mudroom
- **Oppholdsrom** — common area (spanning multiple rooms)
- **Bod** — storage room
- **Bad** — bathroom
- **Vaskerom** — laundry room

### Packages

Files in `packages/` are complete, self-contained feature slices — each defines `input_number`, `template` sensors, and `automation` blocks together.

| Package | Purpose |
|---|---|
| `zigbee_offline_watchdog.yaml` | Monitors Zigbee devices by label `zigbee_watchlist`, sends persistent + mobile alerts |
| `varmekabel.yaml` | Controls outdoor frost protection heating cable (heat pump drainage) via `switch.ute_varmekabel_varmepumpe` based on outdoor temperature. Thresholds configurable via `input_number.varmekabel_temp_pa` (+2°C) and `input_number.varmekabel_temp_av` (+4°C). Locks cable ON if `sensor.ute_netatmo_korr` becomes unavailable. |
| `hytte_avreise.yaml` | 3-state cabin heating machine (`input_select.hytte_status`: ledig/planlagt/ankommet). Defines all `input_number` and `input_datetime` helpers for arrival/departure. Scripts live in `scripts.yaml`. State persists across HA restarts (no `initial:` on the input_select). |
| `bod_frostvakt.yaml` | Frost protection for storage room (bod): turns hot water heater (bereder) ON via Google Assistant when either bod sensor drops below threshold, OFF when both exceed the upper threshold and status is `ledig`. Configurable thresholds via `input_number.bod_frostvakt_temp_pa` (default 10°C) and `input_number.bod_frostvakt_temp_av` (default 12°C). Sensors: `sensor.bod_temperaturmaler_temperature` and `sensor.bod_temperatur`. |

### Lovelace Dashboards

`lovelace/hytte/tjukktommern.yaml` is the main dashboard. `lovelace/hytte/oppholdsrom.yaml` is the **Mobil** view (first tab) — included via `!include`. Each view must be wrapped in a `vertical-stack` card to prevent HA's desktop multi-column layout from breaking the card order.

The Mobil view contains:
- Chips row: alarm state, outdoor temperature, Yr weather, varmekabel status (VK: På/Av/Sikker)
- Climate control (Daikin + temperature graph)
- Avreise/Ankomst heating control (3-state: ledig → planlagt → ankommet) with script-state-aware buttons
- Scene buttons + active lights grouped by room (Stue → Gang → Kjøkken → Spisestue)
- Open doors/windows (auto-hidden when none open)

`lovelace/hytte/temperatur_innstillinger.yaml` is a separate settings tab (only visible to a specific user). It contains sliders for departure/arrival temperatures (Daikin + Mill), pre-heating lead times (Varmepumpe/Sikom/Mill), planned start times, varmekabel drainage thresholds, and bod frost protection thresholds.

### Temperature Sensor Fusion (`configuration.yaml`)

A virtual stue temperature sensor (`sensor.stue_temperatur_virtuell`) blends Netatmo and Sensibo with context-aware weights:
- Morning sun (7–11 AM, sun elevation > 5°): Sensibo 80% / Netatmo 20%
- Rapid heating detected (rate ≥ 1°C/h): shifts weight further to Sensibo
- Fallback to simple average when sensors diverge > 3°C

The virtual outdoor temperature (`sensor.ute_temperatur_virtuell`) is a passthrough of `sensor.ute_netatmo_korr` only — Daikin outdoor was removed because the heat pump's operation causes unreliable readings in cold weather.

### Cabin Heating Control (Avreise/Ankomst)

State machine with three states in `input_select.hytte_status`: `ledig` (vacant), `planlagt` (arrival planned), `ankommet` (arrived).

**Scripts in `scripts.yaml`:**
- `planlegg_ankomst` — validates arrival time is in the future, sets all three start datetimes upfront (Varmepumpe/Sikom/Mill), starts heating immediately if lead time has already passed, sets status to `planlagt`
- `forlat_hytta` — sets Sikom/bereder to eco/off, sets Daikin+Mill to departure temps, sets status to `ledig`
- `ankomst_hytta` — sets Sikom/bereder to comfort/on, sets Daikin+Mill to arrival temps, sets status to `ankommet`
- `avbryt_planlegging` — resets status to `ledig` and resets arrival time to next Friday
- `varme_paa_override` — calls `ankomst_hytta` directly (override from `ledig` or `planlagt`)

**Scheduled start automations in `automations.yaml`:** `ankomst_varmepumpe_start`, `ankomst_sikom_start`, `ankomst_mill_start` — each triggers at its respective `input_datetime`, checks status is `planlagt`, then starts that heating system.

**State persistence:** `input_select` has no `initial:` so HA restores state from recorder. The `ankomst_reset_default_tidspunkt` startup automation resets to `ledig` only when status is not `ankommet` and arrival time is past.

**Time calculation:** Uses `state_attr('input_datetime.ankomst_tidspunkt', 'timestamp') - now().timestamp()` (epoch arithmetic) to avoid timezone ambiguity. Start datetimes use `strftime('%Y-%m-%d %H:%M:%S')` — never `isoformat()` which produces a T-separator that `input_datetime.set_datetime` cannot parse (causes 1970 epoch).

**Sikom/bereder** (underfloor heating + hot water) is controlled via `google_assistant_sdk.send_text_command` — no direct HA entity. Commands: `"set <room> to comfort/eco mode"`, `"set bereder to on/off"`. See the dedicated section below for full details.

### Sikom Underfloor Heating

Sikom is a Norwegian underfloor heating system installed in three rooms: **gang** (hallway), **bad** (bathroom), and **vaskerom** (laundry room). The hot water heater (**bereder**) is also integrated via the same Sikom system.

**Integration:** There is no native Home Assistant integration for Sikom. All control goes through `google_assistant_sdk.send_text_command` — HA sends voice commands to Google Assistant which relays them to the Sikom system. This means:
- HA cannot read the current Sikom state (no feedback/sensor)
- Commands are fire-and-forget — HA does not know if they succeeded
- A **3-second delay** is required between consecutive commands or the Sikom bridge drops them

**Google Assistant SDK** (`google_assistant_sdk`) is a built-in HA integration (not HACS). It authenticates via OAuth2 against a Google Cloud project. The access token renews automatically every hour via the stored refresh token — no manual key renewal is normally needed. `language_code` is set to `en-US`, so **all commands must be written in English**. If the integration stops working, re-authenticate in HA Settings → Devices & Services → Google Assistant SDK. The refresh token can be invalidated by Google if unused for 6+ months or if access is revoked in the Google account's security settings.

**Available commands:**
```
"set gang to comfort mode"
"set bad to comfort mode"
"set vaskerom to comfort mode"
"set gang to eco mode"
"set bad to eco mode"
"set vaskerom to eco mode"
"set bereder to on"
"set bereder to off"
```

**Modes:**
- `comfort` — active heating to setpoint (used on arrival)
- `eco` — reduced setback temperature (used on departure/vacancy)

**Bereder** (hot water heater) is physically located in the **bod** (storage room). It is turned off by default to save electricity, and controlled by two systems: the arrival/departure scripts, and the bod frost protection (`bod_frostvakt.yaml`). The frostvakt takes priority — it turns bereder on regardless of status when bod temperature drops below threshold, and only turns it off when status is `ledig`.

**Sikom app:** The Sikom app is a separate mobile app that should be checked manually after triggering comfort mode, as there is no HA confirmation that the command was received. Dashboard buttons include a reminder: *"Husk å sjekke Sikom-appen!"*.

**Never call Sikom commands in rapid succession** — always insert a `delay: "00:00:03"` between each command in scripts and automations.

### xComfort Lighting

xComfort is a legacy bus system that communicates **via MQTT** through the local xComfort addon. The `lys_alt_av` script in `scripts.yaml` handles its quirks: it sets brightness to 0 first, then turns off, with retries — direct `turn_off` calls are unreliable. Always use this script (or replicate its pattern) when turning off xComfort lights.

MQTT device triggers for xComfort buttons use `domain: mqtt` with `device_id` — same format as other MQTT buttons.

### IKEA Zigbee Bulbs

IKEA Zigbee bulbs (`light.stue_5x_spott` etc.) may turn back on after being switched off if they lose and re-establish Zigbee connectivity, as they restore previous state on reconnect. The alarm automation includes a 2-minute delayed re-off as a workaround.

### Battery Monitoring

Handled by the `sbyx` blueprint (`blueprints/automation/sbyx/low-battery-level-detection-notification-for-all-battery-sensors.yaml`) configured in `automations.yaml`.

**What is monitored:** All HA sensors with `device_class: battery` — includes Zigbee sensors (temperature, door contacts), xComfort wireless buttons, Netatmo rain gauge, and any other battery-reporting device.

**Settings:**
- Threshold: **40%** — intentionally higher than the blueprint default (20%) because some Zigbee sensors become unreliable well above 20% before the reported level catches up
- Frequency: **Mondays at 10:00** (`day: 1`)
- Excluded: all `mobile_app` entities filtered dynamically via `integration_entities('mobile_app')` in the message template — no hardcoded phone entity IDs needed

**Notifications sent:** both `notify.notify` (mobile push) and `persistent_notification.create` (HA bell icon in browser).

**Message format:** `"Sensor name: 36 % (Room)"` — uses `area_name(state.entity_id)` to show which room the device is in. Devices without an assigned area show name and percentage only.

**Note:** The blueprint's `sensors` condition variable is computed independently of our custom message template. If only mobile phones are below threshold, the condition may still pass but the message will be empty (phones are filtered in the template, not in the blueprint's variable).

### Notifications

All notifications use `notify.notify` (broadcasts to all registered mobile apps) rather than device-specific `notify.mobile_app_*` targets. Persistent notifications (`persistent_notification.create`) are added alongside mobile push for anything that should also be visible in the HA browser UI.

### Secrets

`secrets.yaml` is gitignored. See `secrets.example.yaml` for the expected keys (MQTT credentials, Verisure credentials). Never commit the real file.
