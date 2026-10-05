#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_FILE="$PROJECT_ROOT/tasmota/user_config_override.h.template"
CONFIG_FILE="$PROJECT_ROOT/tasmota/user_config_override.h"

# 1Password configuration
OP_ACCOUNT="my.1password.com"
OP_ITEM="Tasmota Firmware Secrets"

# Default build target
BUILD_TARGET="${1:-tasmota}"
shift || true

# Additional build flags (e.g., -DFIRMWARE_AC_CONTROLLER)
BUILD_FLAGS="${*:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

cleanup() {
    if [[ -f "$CONFIG_FILE" ]]; then
        info "Cleaning up generated config file..."
        rm -f "$CONFIG_FILE"
    fi
}

trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    if ! command -v op &> /dev/null; then
        error "1Password CLI (op) not found. Install from: https://developer.1password.com/docs/cli/"
        exit 1
    fi

    if ! command -v pio &> /dev/null; then
        error "PlatformIO CLI (pio) not found. Install from: https://platformio.org/install/cli"
        exit 1
    fi

    if ! op account get --account "$OP_ACCOUNT" &> /dev/null; then
        error "Not signed in to 1Password account: $OP_ACCOUNT"
        error "Run: op signin --account $OP_ACCOUNT"
        exit 1
    fi

    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        error "Template file not found: $TEMPLATE_FILE"
        exit 1
    fi
}

# Mask a secret value for logging (first 2 + last 2 chars, or fully masked if < 10 chars)
mask_secret() {
    local value="$1"
    if [[ ${#value} -ge 10 ]]; then
        echo "${value:0:2}...${value: -2}"
    else
        echo "****"
    fi
}

# Fetch a secret from 1Password
fetch_secret() {
    local field="$1"
    local value
    value=$(op item get "$OP_ITEM" --account "$OP_ACCOUNT" --fields "$field" 2>/dev/null)
    if [[ -z "$value" ]]; then
        error "Failed to fetch secret: $field"
        exit 1
    fi
    info "  $field = $(mask_secret "$value")" >&2
    echo "$value"
}

# Generate config file from template
generate_config() {
    info "Fetching secrets from 1Password..."

    local wifi_ssid wifi_pass influxdb_host influxdb_org influxdb_token mqtt_host mqtt_user mqtt_pass

    wifi_ssid=$(fetch_secret "wifi_ssid")
    wifi_pass=$(fetch_secret "wifi_pass")
    influxdb_host=$(fetch_secret "influxdb_host")
    influxdb_org=$(fetch_secret "influxdb_org")
    influxdb_token=$(fetch_secret "influxdb_token")
    mqtt_host=$(fetch_secret "mqtt_host")
    mqtt_user=$(fetch_secret "mqtt_user")
    mqtt_pass=$(fetch_secret "mqtt_pass")

    info "Generating config file..."

    sed -e "s|{{WIFI_SSID}}|$wifi_ssid|g" \
        -e "s|{{WIFI_PASS}}|$wifi_pass|g" \
        -e "s|{{INFLUXDB_HOST}}|$influxdb_host|g" \
        -e "s|{{INFLUXDB_ORG}}|$influxdb_org|g" \
        -e "s|{{INFLUXDB_TOKEN}}|$influxdb_token|g" \
        -e "s|{{MQTT_HOST}}|$mqtt_host|g" \
        -e "s|{{MQTT_USER}}|$mqtt_user|g" \
        -e "s|{{MQTT_PASS}}|$mqtt_pass|g" \
        -e "s|// {{SECRETS_SENTINEL}}|#define SECRETS_INJECTED 1|" \
        "$TEMPLATE_FILE" > "$CONFIG_FILE"

    # Validate: no remaining placeholders
    local remaining
    remaining=$(grep -c '{{[A-Z_]*}}' "$CONFIG_FILE" || true)
    if [[ "$remaining" -gt 0 ]]; then
        error "Found $remaining un-substituted placeholder(s) in generated config:"
        grep '{{[A-Z_]*}}' "$CONFIG_FILE" >&2
        exit 1
    fi

    local define_count
    define_count=$(grep -c '#define' "$CONFIG_FILE" || true)
    info "Config file generated: $CONFIG_FILE ($define_count #define lines, 0 remaining placeholders)"
}

# Run PlatformIO build
run_build() {
    info "Building target: $BUILD_TARGET"

    local pio_args=("-e" "$BUILD_TARGET")

    if [[ -n "$BUILD_FLAGS" ]]; then
        info "Additional build flags: $BUILD_FLAGS"
        export PLATFORMIO_BUILD_FLAGS="-DUSE_CONFIG_OVERRIDE $BUILD_FLAGS"
    else
        export PLATFORMIO_BUILD_FLAGS="-DUSE_CONFIG_OVERRIDE"
    fi

    cd "$PROJECT_ROOT"
    pio run "${pio_args[@]}"

    info "Build complete!"
    info "Firmware location: $PROJECT_ROOT/.pio/build/$BUILD_TARGET/"
}

main() {
    info "Tasmota build script with 1Password secrets"
    info "============================================"

    check_prerequisites
    generate_config
    run_build

    info "Done!"
}

main
