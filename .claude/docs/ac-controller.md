# AC Controller (MiElHVAC)

An ESP-01 running this fork's `tasmota-ac-controller` build (`-DFIRMWARE_AC_CONTROLLER`) talks directly to a Mitsubishi indoor unit's CN105 connector over Tasmota's MiElHVAC driver (`tasmota/tasmota_xdrv_driver/xdrv_44_miel_hvac.ino`), and publishes/subscribes over MQTT as a Home Assistant climate entity. Two are deployed: `upstairs_ac` (192.168.1.116, `Upstairs AC Controller`) and `downstairs_ac` (192.168.1.117, `Downstairs AC Controller`). Each unit's MQTT topic and friendly name are set manually after flashing — the shared firmware image has no device-specific identity baked in.

## Known failure mode: feeding CN105's 5V straight into a bare ESP-01

CN105 supplies 5V, not 3.3V, and a bare ESP-01 module has no onboard regulator — it needs exactly 3.3V on VCC. `upstairs_ac`'s original assembly fed CN105 pin 3 (5V) directly into the ESP-01, with no regulator in between. It ran for 645 days (~21 months, installed 2024-11-28, last reported 2026-09-05) before failing outright, then sat offline for 27 days before being replaced (confirmed from the `tasmota` InfluxDB bucket: first/last points per device, `device=upstairs_ac`). `downstairs_ac` is wired the same way and has run continuously since 2024-12-01 with no gaps as of this writing, so the failure isn't instant or guaranteed — more likely a slow overvoltage stress that eventually takes the chip out, on an unpredictable timeline.

The fix for any future build or repair: put a 5V→3.3V LDO regulator (AMS1117-3.3 or LD1117V33, either works — IN/GND/OUT, no other parts needed) between CN105 pin 3 and the ESP-01's VCC. Do not wire CN105's 5V to the ESP-01 directly, even though it "works" for a while.

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
- `INFLUXDB_SKIP_KEYS` → the five `MiElHVAC` keys that carry raw packet hex dumps (`Settings`, `RoomTemp`, `Timers`, `Status`, `Stage`). The Influxdb driver (`xdrv_59_influxdb.ino`) stores any string made only of digits as a number, so a dump with no A–F lands in the `tasmota` bucket as a huge fake value (millions of points of `stage` and `timers`). The list holds `sensor.key` names, so other drivers' `Status` and the `OperationStage`/`FanStage`/`ModeStage` keys are unaffected, and the dumps stay on MQTT. Stock builds leave the list empty.

## The remote-temp boot rule

Both units get their room temperature from a `cutie` weather station (`skeppsholmen` for `upstairs_ac`, `vaxholm` for `downstairs_ac`) publishing to `cmnd/<topic>/HVACRemoteTemp` on a ~60s cadence — see `~/.claude/docs/cutie-fleet.md`. The MiElHVAC driver's remote-temp auto-clear timeout (`HVACRemoteTempClearTime`) defaults to 10 seconds and lives only in RAM (`remotetemp_auto_clear_time` in `xdrv_44_miel_hvac.ino`, never read from or written to flash settings) — it resets to that default on every boot, regardless of firmware. With the default 10s window and a ~60s publish cadence, the remote sensor value clears and re-arms once a minute, which shows up in Home Assistant as the thermostat's temperature source intermittently flapping.

There's no compile-time macro for `HVACRemoteTempClearTime` itself (unlike `SERIAL_LOG_LEVEL`/`TEMP_CONVERSION` above) — it can only be set with a Rule, a runtime setting (`Settings->rules`). But `user_config_override.h.template`'s `FIRMWARE_AC_CONTROLLER` block installs that rule automatically via stock Tasmota's `USER_RULE1`/`USER_BACKLOG` hooks (`my_user_config.h`), which `SettingsDefault()` applies on first boot and on `Reset 1`/`2`/`4`/`5`/`6` (`tasmota_support/settings.ino`) — covering both a raw fresh flash and the `Reset 5` step in Flashing gotchas below. No manual command is needed after flashing. Confirm with `Rule1` (no argument) — `State` should read `ON` and `Rules` should read `ON System#Boot DO HVACRemoteTempClearTime 300000 ENDON`.

Both currently-deployed units already carry this rule from before it was compiled in — `downstairs_ac` manually for 9+ months, `upstairs_ac` applied live via MQTT on 2026-10-08 — so neither needed a reflash when this became part of the template.

## Flashing gotchas (bare ESP-01 + USB/UART adapter, no dedicated programmer)

- CH_PD must be bridged to VCC for the chip to run at all — it's the chip-enable pin, and a bare breakout board doesn't tie it internally. This draws negligible current; it's not a power-rail concern.
- GPIO0 must reach GND for the ROM bootloader to answer, and the ground connection has to be made _before_ power is applied and held through the whole esptool session — letting go right as power comes up is the same as never grounding it.
- Identify and write in one esptool invocation (`write-flash` alone does both), not two separate processes. Reopening the serial port between an identify step and a write step glitches DTR/RTS on some adapters and knocks the chip out of bootloader mode before the write can start — this looks like "the chip stopped responding" mid-write, but it's a port-reopen artifact, not a wiring or power problem.
