# Tasmota Fork

## Build System

- PlatformIO-based builds
- Use `./scripts/build-with-secrets.sh` to build with secrets from 1Password
- Secrets stored in 1Password (my.1password.com, Private vault, "Tasmota Firmware Secrets" item)

## Configuration

- `tasmota/user_config_override.h` is gitignored and generated at build time
- `tasmota/user_config_override.h.template` contains placeholders (`{{...}}`) for secrets
- Non-secret config (location, timezone, device templates) lives in the template

## AC Controller (MiElHVAC)

See `.claude/docs/ac-controller.md` for CN105 wiring, the known 5V-direct-to-ESP01 failure mode, required firmware defaults (SerialLog/TEMP_CONVERSION/Module), and flashing gotchas.

## Branches

- `development` - the only branch. The 1Password secrets integration (previously on `secrets-to-1password`) was merged in on 2026-10-05, and `master`/`patch-1`/`secrets-to-1password` were deleted the same day.

## Secrets (DO NOT COMMIT)

- WiFi credentials (STA_SSID1, STA_PASS1)
- MQTT credentials (MQTT_HOST, MQTT_USER, MQTT_PASS)
- InfluxDB credentials (INFLUXDB_HOST, INFLUXDB_ORG, INFLUXDB_TOKEN)
