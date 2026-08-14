# Building Tasmota Firmware

This document describes how to build Tasmota firmware with secrets managed via 1Password.

## Prerequisites

### 1Password CLI

Install the 1Password CLI:

```bash
brew install --cask 1password/tap/1password-cli
```

Sign in to your account:

```bash
op signin --account my.1password.com
```

### PlatformIO

Install PlatformIO Core (CLI):

```bash
brew install platformio
```

Or via pip:

```bash
pip install platformio
```

## Building Firmware

### Basic Build

Build the default `tasmota` target:

```bash
./scripts/build-with-secrets.sh
```

### Specific Target

Build a specific PlatformIO environment (e.g., ESP32):

```bash
./scripts/build-with-secrets.sh tasmota32
```

### Custom Firmware Flags

Build with firmware-specific flags:

```bash
# AC Controller firmware
./scripts/build-with-secrets.sh tasmota -DFIRMWARE_AC_CONTROLLER

# Light Switch (ESP32)
./scripts/build-with-secrets.sh tasmota32 -DFIRMWARE_LIGHT_SWITCH

# MJS01 Light Switch
./scripts/build-with-secrets.sh tasmota -DFIRMWARE_MJS01_LIGHT_SWITCH

# Smart Switch
./scripts/build-with-secrets.sh tasmota -DFIRMWARE_SMART_SWITCH
```

### Output Location

Built firmware is located at:

```
.pio/build/<target>/firmware.bin
```

## Secrets Management

Secrets are stored in 1Password under the item **"Tasmota Firmware Secrets"** in the **Private** vault.

### Secret Fields

| Field            | Description                                     |
| ---------------- | ----------------------------------------------- |
| `wifi_ssid`      | WiFi network name                               |
| `wifi_pass`      | WiFi password                                   |
| `influxdb_host`  | InfluxDB server URL                             |
| `influxdb_org`   | InfluxDB organization                           |
| `influxdb_token` | InfluxDB authentication token                   |
| `mqtt_host`      | Local Mosquitto broker address (192.168.1.3)    |
| `mqtt_user`      | MQTT username (dedicated `tasmota` broker user) |
| `mqtt_pass`      | MQTT password                                   |

### Updating Secrets

Update a secret via CLI:

```bash
op item edit "Tasmota Firmware Secrets" --vault Private --account my.1password.com \
  wifi_ssid="NewSSID"
```

Or edit interactively:

```bash
op item edit "Tasmota Firmware Secrets" --vault Private --account my.1password.com
```

### Viewing Secrets

```bash
op item get "Tasmota Firmware Secrets" --vault Private --account my.1password.com --reveal
```

## How It Works

1. `build-with-secrets.sh` fetches secrets from 1Password
2. Secrets are injected into `tasmota/user_config_override.h.template` to generate `user_config_override.h`
3. PlatformIO builds the firmware with the generated config
4. The generated `user_config_override.h` is cleaned up after the build

The generated config file is in `.gitignore` to prevent accidental commits.

## Troubleshooting

### "Not signed in to 1Password"

Run:

```bash
op signin --account my.1password.com
```

### "1Password CLI not found"

Install via Homebrew:

```bash
brew install --cask 1password/tap/1password-cli
```

### "PlatformIO not found"

Install via Homebrew or pip:

```bash
brew install platformio
# or
pip install platformio
```

### "Failed to fetch secret"

Verify the 1Password item exists and has the correct field names:

```bash
op item get "Tasmota Firmware Secrets" --vault Private --account my.1password.com
```

### Build Errors

Check that the template file exists:

```bash
ls tasmota/user_config_override.h.template
```

View build logs for detailed errors:

```bash
pio run -e tasmota -v
```
