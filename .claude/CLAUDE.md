# Tasmota Fork

## Build System
- PlatformIO-based builds
- Use `./scripts/build-with-secrets.sh` to build with secrets from 1Password
- Secrets stored in 1Password (my.1password.com, Private vault, "Tasmota Firmware Secrets" item)

## Configuration
- `tasmota/user_config_override.h` is gitignored and generated at build time
- `tasmota/user_config_override.h.template` contains placeholders (`{{...}}`) for secrets
- Non-secret config (location, timezone, device templates) lives in the template

## Branches
- `development` - main working branch (synced with upstream)
- `secrets-to-1password` - clean branch with 1Password integration
- `master`, `patch-1` - other branches

## Secrets (DO NOT COMMIT)
- WiFi credentials (STA_SSID1, STA_PASS1)
- MQTT credentials (MQTT_HOST, MQTT_USER, MQTT_PASS)
- InfluxDB credentials (INFLUXDB_HOST, INFLUXDB_ORG, INFLUXDB_TOKEN)
