# Tasmota Fork

## Build System

- PlatformIO-based builds
- Use `./scripts/build-with-secrets.sh` to build with secrets from 1Password
- Secrets stored in 1Password (my.1password.com, Private vault, "Tasmota Firmware Secrets" item)

## Configuration

- `tasmota/user_config_override.h` is gitignored and generated at build time
- `tasmota/user_config_override.h.template` contains placeholders (`{{...}}`) for secrets
- Non-secret config (location, timezone, device templates) lives in the template

## Making config changes

When a device needs non-default behavior, prefer in this order:

1. An explicit compile-time flag — a `#define` in `user_config_override.h.template` — when one already exists for the setting (e.g. `SERIAL_LOG_LEVEL`, `TEMP_CONVERSION`).
2. `USER_RULE1`/`USER_RULE2`/`USER_RULE3`/`USER_BACKLOG` in the template when the setting can only be reached via a runtime command (`Rule`, `SetOption`, etc.) — these run automatically via `SettingsDefault()` on first boot or `Reset 1`/`2`/`4`/`5`/`6`, so no manual command is needed after flashing.
3. Editing the driver's `.ino` source directly, only when neither of the above can reach the setting.

## AC Controller (MiElHVAC)

See `.claude/docs/ac-controller.md` for CN105 wiring, the known 5V-direct-to-ESP01 failure mode, required firmware defaults (SerialLog/TEMP_CONVERSION/Module), and flashing gotchas.

## Branches

- `development` - the only branch. The 1Password secrets integration (previously on `secrets-to-1password`) was merged in on 2026-10-05, and `master`/`patch-1`/`secrets-to-1password` were deleted the same day.

## Secrets (DO NOT COMMIT)

- WiFi credentials (STA_SSID1, STA_PASS1)
- MQTT credentials (MQTT_HOST, MQTT_USER, MQTT_PASS)
- InfluxDB credentials (INFLUXDB_HOST, INFLUXDB_ORG, INFLUXDB_TOKEN)
