# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Home Assistant configuration repository for a Norwegian cabin called **Tjukktømmern**. It runs Home Assistant Core 2025.9.4 and manages lighting (Eaton xComfort + Zigbee), climate (Daikin heat pump, Sensibo, Netatmo), and security (Verisure alarm).

## Validation & Maintenance Commands

```bash
# Validate xComfort local addon structure before deploying
bash validate_xcomfort_addon.sh

# Export addon state and push to git (runs as cron on the HA host)
bash tools/export_addons.sh
```

There is no build/lint/test pipeline — Home Assistant validates configuration at startup. The only way to verify YAML correctness is via the HA Developer Tools > YAML validation in the UI, or by restarting Home Assistant.

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
| `custom_components/` | Third-party integrations not in HA core |
| `addons_local/` | Local custom HA addons (xComfort bridge) |
| `xcomfort_datapoints.yaml` | Eaton xComfort device ID ↔ entity mapping |
| `zigbee2mqtt/` | Zigbee2MQTT broker config and device database |

### Norwegian Room Names

Scenes and entities use Norwegian names. Key rooms:
- **Stue** — living room
- **Kjøkken** — kitchen
- **Spisestue** — dining room
- **Gang** — hallway
- **Vindfang** — entryway/mudroom
- **Oppholdsrom** — common area (spanning multiple rooms)
- **Bod** — storage room

### Packages Pattern

Files in `packages/` are complete, self-contained feature slices — each can define `input_number`, `template` sensors, and `automation` blocks together. Currently: `zigbee_offline_watchdog.yaml` (monitors Zigbee devices by label `zigbee_watchlist`, sends persistent + mobile alerts).

### Temperature Sensor Fusion (`configuration.yaml`)

A virtual room temperature sensor blends Netatmo (outdoor-influenced) and Sensibo (indoor) readings with context-aware weights:
- Morning sun (7–11 AM, sun elevation > 5°): Sensibo 80% / Netatmo 20%
- Rapid heating detected (rate ≥ 1°C/h via derivative sensor): shifts weight further to Sensibo
- Fallback to simple average when sensors diverge > 3°C

### xComfort Lighting

xComfort is a legacy bus system. The `lys_alt_av` script in `scripts.yaml` handles its quirks: it sets brightness to 0 first, then turns off, with retries — direct `turn_off` calls are unreliable on xComfort entities. Always use this script (or replicate its pattern) when turning off xComfort lights.

### Git-Based Config Backup

`tools/export_addons.sh` runs as a cron job on the HA host. It:
1. Copies local addons from `/addons/local` into `addons_local/`
2. Exports addon metadata to `addons_state/`
3. Commits and pushes to this repo

Snapshot commits (subject: `addons snapshot …`) are automated — don't be confused by them in git log.

### Secrets

`secrets.yaml` is gitignored. See `secrets.example.yaml` for the expected keys (MQTT credentials, Verisure credentials). Never commit the real file.
