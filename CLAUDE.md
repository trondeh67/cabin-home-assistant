# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Home Assistant configuration repository for a Norwegian cabin called **Tjukktømmern**. It manages lighting (Eaton xComfort + Zigbee), climate (Daikin heat pump, Sensibo, Netatmo), security (Verisure alarm), and outdoor frost protection (varmekabel).

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
| `scripts.yaml` | Reusable scripts (all-lights-off with xComfort retries, scene restoration) |
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
| `varmekabel.yaml` | Controls outdoor frost protection heating cable via `switch.ute_varmekabel_varmepumpe` based on outdoor temperature. Thresholds configurable via `input_number.varmekabel_temp_pa` (+2°C) and `input_number.varmekabel_temp_av` (+4°C). Locks cable ON if `sensor.ute_netatmo_korr` becomes unavailable. |

### Lovelace Dashboards

`lovelace/hytte/tjukktommern.yaml` is the main dashboard. `lovelace/hytte/oppholdsrom.yaml` is the **Mobil** view (first tab) — included via `!include`. Each view must be wrapped in a `vertical-stack` card to prevent HA's desktop multi-column layout from breaking the card order.

The Mobil view contains:
- Chips row: alarm state, outdoor temperature, Yr weather, varmekabel status (VK: På/Av/Sikker)
- Climate control (Daikin + temperature graph)
- Scene buttons + active lights grouped by room (Stue → Gang → Kjøkken → Spisestue)
- Open doors/windows (auto-hidden when none open)

### Temperature Sensor Fusion (`configuration.yaml`)

A virtual stue temperature sensor (`sensor.stue_temperatur_virtuell`) blends Netatmo and Sensibo with context-aware weights:
- Morning sun (7–11 AM, sun elevation > 5°): Sensibo 80% / Netatmo 20%
- Rapid heating detected (rate ≥ 1°C/h): shifts weight further to Sensibo
- Fallback to simple average when sensors diverge > 3°C

The virtual outdoor temperature (`sensor.ute_temperatur_virtuell`) is a passthrough of `sensor.ute_netatmo_korr` only — Daikin outdoor was removed because the heat pump's operation causes unreliable readings in cold weather.

### xComfort Lighting

xComfort is a legacy bus system that communicates **via MQTT** through the local xComfort addon. The `lys_alt_av` script in `scripts.yaml` handles its quirks: it sets brightness to 0 first, then turns off, with retries — direct `turn_off` calls are unreliable. Always use this script (or replicate its pattern) when turning off xComfort lights.

MQTT device triggers for xComfort buttons use `domain: mqtt` with `device_id` — same format as other MQTT buttons.

### IKEA Zigbee Bulbs

IKEA Zigbee bulbs (`light.stue_5x_spott` etc.) may turn back on after being switched off if they lose and re-establish Zigbee connectivity, as they restore previous state on reconnect. The alarm automation includes a 2-minute delayed re-off as a workaround.

### Secrets

`secrets.yaml` is gitignored. See `secrets.example.yaml` for the expected keys (MQTT credentials, Verisure credentials). Never commit the real file.
