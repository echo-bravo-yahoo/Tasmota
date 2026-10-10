# AC Controller (MiElHVAC)

An ESP-01 running this fork's `tasmota-ac-controller` build (`-DFIRMWARE_AC_CONTROLLER`) talks directly to a Mitsubishi indoor unit's CN105 connector over Tasmota's MiElHVAC driver (`tasmota/tasmota_xdrv_driver/xdrv_44_miel_hvac.ino`), and publishes/subscribes over MQTT as a Home Assistant climate entity. Two are deployed: `upstairs_ac` (192.168.1.116, `Upstairs AC Controller`) and `downstairs_ac` (192.168.1.117, `Downstairs AC Controller`). Each unit's MQTT topic and friendly name are set manually after flashing — the shared firmware image has no device-specific identity baked in.

## Known failure mode: feeding CN105's 5V straight into a bare ESP-01

CN105 supplies 5V, not 3.3V, and a bare ESP-01 module has no onboard regulator — it needs exactly 3.3V on VCC. `upstairs_ac`'s original assembly fed CN105 pin 3 (5V) directly into the ESP-01, with no regulator in between. It ran for 645 days (~21 months, installed 2024-11-28, last reported 2026-09-05) before failing outright, then sat offline for 27 days before being replaced (confirmed from the `tasmota` InfluxDB bucket: first/last points per device, `device=upstairs_ac`). `downstairs_ac` is wired the same way and has run continuously since 2024-12-01 with no gaps as of this writing, so the failure isn't instant or guaranteed — more likely a slow overvoltage stress that eventually takes the chip out, on an unpredictable timeline.

The fix for any future build or repair: put a 5V→3.3V LDO regulator (AMS1117-3.3 or LD1117V33, either works — IN/GND/OUT, no other parts needed) between CN105 pin 3 and the ESP-01's VCC. Do not wire CN105's 5V to the ESP-01 directly, even though it "works" for a while.

## Replacing a board: re-key the DHCP reservation

Each controller's address comes from a reservation on the router (FreshTomato at 192.168.1.1, `nvram get dhcpd_static`, entries shaped `MAC<IP<hostname<0`). The reservation is keyed on the ESP-01's MAC, and a replacement ESP-01 has a different MAC, so it takes a dynamic lease from the pool (.128–.250) and stops answering at the controller's address. `upstairs_ac` ran at 192.168.1.221 after its board was replaced because the .116 reservation still carried the dead board's MAC (`EC:FA:BC:37:3D:8D`); the live board is `80:7D:3A:16:87:0D`, and the entry was re-keyed on 2026-10-09.

After swapping a board, replace the MAC in that one entry, run `nvram commit` and `service dnsmasq restart`, then send `Restart 1` to the board so it renews its lease. Do all router work in one `ssh router` call, because the router bans a source after three new SSH connections in 60 seconds. The Home Assistant device "Upstairs" (firmware 15.2.0.2) is the dead board's registry entry and is stale.

## CN105 wiring

| CN105 pin | Signal        | Goes to                                |
| --------- | ------------- | -------------------------------------- |
| 1         | 12V           | not used                               |
| 2         | GND           | regulator GND + ESP-01 GND             |
| 3         | 5V            | regulator IN                           |
| 4         | AC TX         | ESP-01 GPIO3 / RX                      |
| 5         | AC RX         | ESP-01 GPIO1 / TX                      |
|           | regulator OUT | ESP-01 VCC (and CH_PD, bridged to VCC) |

CN105's TX/RX pin assignment isn't universal across Mitsubishi models — if `Status 10`'s `MiElHVAC` reads as an empty `{}` after wiring (driver running but not exchanging data with the unit), swap which physical pin GPIO1/GPIO3 connect to before assuming anything else is wrong.

## Firmware defaults that matter

`tasmota/user_config_override.h.template`'s `FIRMWARE_AC_CONTROLLER` block sets these so a fresh flash works without manual follow-up commands (as of the fix in commit `fc98d6160`):

- `SERIAL_LOG_LEVEL` → `LOG_LEVEL_NONE` (`SerialLog 0`). The MiElHVAC driver needs sole use of the UART0 pins (GPIO1/GPIO3) to talk to the indoor unit; Tasmota's own console logging over serial competes for the same pins and silently keeps the driver from ever claiming them — it compiles in but `Status 4`'s `Drivers` list shows `!44` instead of `44`, with no error anywhere.
- `TEMP_CONVERSION` → `false` (`SetOption8 0`). Home Assistant's MQTT climate config for both AC units declares `temperature_unit: "C"` and does its own C→F conversion for display. The fork-wide default is Fahrenheit (for other device types' own web UIs); reporting Fahrenheit here gets converted a second time, showing roughly double the real temperature in HA.
- `MODULE`/`FALLBACK_MODULE` → `USER_MODULE`, activating the compiled `USER_TEMPLATE` (GPIO1/GPIO3 remapped to the MiElHVAC TX/RX functions) by default. This one doesn't need a firmware fix — it already works on a normal flash+install — but Tasmota's own quick-power-cycle safeguard can silently flip the live `Module` setting back to a generic board (observed: "Sonoff Basic") if the device gets power-cycled rapidly many times in a row (e.g. while bench-debugging a flaky adapter connection). Symptom is identical to the SerialLog gap (`Drivers` shows `!44`) but the fix is different: send `Module 0` (not `Module 255` — that's an invalid value and silently no-ops) and restart.
- `INFLUXDB_SKIP_KEYS` → the five `MiElHVAC` keys that carry raw packet hex dumps (`Settings`, `RoomTemp`, `Timers`, `Status`, `Stage`). The Influxdb driver (`xdrv_59_influxdb.ino`) stores any string made only of digits as a number, so a dump with no A–F lands in the `tasmota` bucket as a huge fake value (millions of points of `stage` and `timers`). The list holds `sensor.key` names, so other drivers' `Status` and the `OperationStage`/`FanStage`/`ModeStage` keys are unaffected, and the dumps stay on MQTT. Stock builds leave the list empty. Both controllers have run this build since 2026-10-09.

## The remote-temp boot rule

Both units get their room temperature from a `cutie` weather station (`skeppsholmen` for `upstairs_ac`, `vaxholm` for `downstairs_ac`) publishing to `cmnd/<topic>/HVACRemoteTemp` on a ~60s cadence — see `~/.claude/docs/cutie-fleet.md`. The MiElHVAC driver's remote-temp auto-clear timeout (`HVACRemoteTempClearTime`) defaults to 10 seconds and lives only in RAM (`remotetemp_auto_clear_time` in `xdrv_44_miel_hvac.ino`, never read from or written to flash settings) — it resets to that default on every boot, regardless of firmware. With the default 10s window and a ~60s publish cadence, the remote sensor value clears and re-arms once a minute, which shows up in Home Assistant as the thermostat's temperature source intermittently flapping.

There's no compile-time macro for `HVACRemoteTempClearTime` itself (unlike `SERIAL_LOG_LEVEL`/`TEMP_CONVERSION` above) — it can only be set with a Rule, a runtime setting (`Settings->rules`). But `user_config_override.h.template`'s `FIRMWARE_AC_CONTROLLER` block installs that rule automatically via stock Tasmota's `USER_RULE1`/`USER_BACKLOG` hooks (`my_user_config.h`), which `SettingsDefault()` applies on first boot and on `Reset 1`/`2`/`4`/`5`/`6` (`tasmota_support/settings.ino`) — covering both a raw fresh flash and the `Reset 5` step in Flashing gotchas below. No manual command is needed after flashing. Confirm with `Rule1` (no argument) — `State` should read `ON` and `Rules` should read `ON System#Boot DO HVACRemoteTempClearTime 300000 ENDON`.

Both currently-deployed units already carry this rule from before it was compiled in — `downstairs_ac` manually for 9+ months, `upstairs_ac` applied live via MQTT on 2026-10-08 — so neither needed a reflash when this became part of the template.

## OTA reflash

Update a working controller over WiFi. Settings (WiFi, MQTT, topic, friendly name, template and `Rule1`) survive an OTA, and the CH_PD/GPIO0 steps below do not apply. Each ESP-01 has 1 MB of flash with 288–356 KB free, so the full image (about 465 KB gzipped) does not fit directly. Tasmota handles this itself: when the upload fails the space check, it fetches the `-minimal` image from the same server, boots it, and the minimal image then fetches the originally requested URL.

1. Build with `./scripts/build-with-secrets.sh`, which produces `build_output/firmware/tasmota.bin.gz`.
2. Put two files in one directory on a LAN host: that image as `accontroller.bin.gz`, and `http://ota.tasmota.com/tasmota/release-15.2.0/tasmota-minimal.bin.gz` as `accontroller-minimal.bin.gz`. Use the minimal image from the release line the fork is based on, so the settings version does not change.
3. Serve the directory with `python3 -m http.server 8000 --bind <host-ip>`. The full image contains the baked WiFi, MQTT and InfluxDB credentials, so stop the server and delete the directory when finished.
4. On the controller, run `OtaUrl http://<host-ip>:8000/accontroller.bin.gz`, then `Upgrade 1`. The server log shows the full image requested and dropped, the minimal image fetched, a restart, then the full image fetched again and a second restart. The whole sequence takes about 2 minutes, and the controller is unavailable in Home Assistant for that time.
5. Run `OtaUrl 1` to restore the compiled-in default URL (`http://ota.tasmota.com/tasmota/release/tasmota-minimal.bin.gz`).

Name the file with no dash and no dot before the extension. Tasmota builds the minimal name by keeping the filename up to its last `-` (or up to the first `.` when there is no dash) and appending `-minimal` and the original extension, so `ac-controller.bin.gz` would be requested as `ac-minimal.bin.gz`.

Do not power-cycle the controller between the two stages, since the chaining flag lives in RTC memory. If the minimal image runs but never requests the full one, send `Upgrade 1` again; `OtaUrl` is kept in settings.

Verify with these checks, over HTTP (`http://<ip>/cm?cmnd=...`) or MQTT (`cmnd/<topic>/...`):

- `Status 2` reports `BuildDateTime` of the new build. The `Version` string is the same across builds of one release, so do not use it as proof.
- `Status 0` keeps the same `Topic`, `FriendlyName`, `IPAddress` and MQTT host. `Status 4`'s `Drivers` lists `44` and `59` without a `!`. `Rule1` still reads `ON System#Boot DO HVACRemoteTempClearTime 300000 ENDON`.
- `Status 10` shows a populated `MiElHVAC` block that still includes `Stage`, `Timers`, `Status` and `RoomTemp`, because the raw bytes stay on MQTT.
- `Status 1` shows `BootCount` up by one and `RestartReason` of `Software/System restart`. The count rises by one rather than two because Tasmota increments it only after 10 seconds of uptime, and the minimal image restarts into the full image before then (observed on both controllers on 2026-10-09). Keep polling `Status 1` for 15 minutes: an unchanged `BootCount` means the board did not reboot.
- In the `tasmota` InfluxDB bucket, `temperature` and `uptimesec` points keep arriving for the device, and no new `stage`, `timers`, `status` or `roomtemp` points appear.

`downstairs_ac` has a web password that nobody has recorded, so HTTP returns 401. Reach it over MQTT with the broker credentials in the "Tasmota Firmware Secrets" 1Password item (`mqtt_user`, `mqtt_pass`): publish to `cmnd/downstairs_ac/<command>` and read `stat/downstairs_ac/#`. A reply on `stat/` is the only proof the command arrived, because the broker silently drops publishes that its ACL denies. `upstairs_ac` has no web password.

## Flashing gotchas (bare ESP-01 + USB/UART adapter, no dedicated programmer)

Serial flashing is only for a board that no longer boots, such as a failed OTA or a fresh ESP-01. Use OTA otherwise.

- CH_PD must be bridged to VCC for the chip to run at all — it's the chip-enable pin, and a bare breakout board doesn't tie it internally. This draws negligible current; it's not a power-rail concern.
- GPIO0 must reach GND for the ROM bootloader to answer, and the ground connection has to be made _before_ power is applied and held through the whole esptool session — letting go right as power comes up is the same as never grounding it.
- Identify and write in one esptool invocation (`write-flash` alone does both), not two separate processes. Reopening the serial port between an identify step and a write step glitches DTR/RTS on some adapters and knocks the chip out of bootloader mode before the write can start — this looks like "the chip stopped responding" mid-write, but it's a port-reopen artifact, not a wiring or power problem.
