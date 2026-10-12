# Light Switch (Sonoff MINIR4)

In-wall light switches running this fork's `tasmota-light-switch` build (`-DFIRMWARE_LIGHT_SWITCH`: a Sonoff MINIR4 template with `SwitchMode1 2`, so the relay follows the rocker position). Build with `./scripts/build-with-secrets.sh tasmota-light-switch`, which produces about 1.4 MB. Do not build `tasmota32 -DFIRMWARE_LIGHT_SWITCH`: that selects the full-featured env and produces about 2.1 MB.

## Deployed switches

The notes vault has one note per deployed switch under `23.01 iot/networking/` (the Notes section of `~/.claude/docs/information-stores.md` says where the vault is mounted). Take a switch's address and identifiers from its note; this doc does not repeat them. The bedroom light switch (`bedroom-light.md`) is the reference for the config comparison below. Each switch has a router DHCP reservation, a dnsmasq name and a SWAG block, described in `~/.claude/docs/swag-lan-subdomains.md`.

## Flash and configure a switch

Run every curl through `cc-cred run` with `WP=op://Private/Tasmota device web login/password`, passing the login in a curl config on stdin (`curl -K -`) so it never appears in a command line.

1. A switch that has never been configured answers `/` and `/cm` without a password. Send `WebPassword2 <password>` first; the reply is `{"WebPassword":"****"}`.
2. Build, and check that the image is between 1.3 and 1.5 MB. Do not grep the image for the version string: Tasmota stores the version as the integer `0x0F020004` (`tasmota/include/tasmota_version.h`), not as text.
3. Serve the image from stockholm, because a server on heron's WSL address is not reachable from the LAN. `scp` the image to `/tmp/light-switch/` on stockholm, then run `ssh stockholm 'timeout 1200 python3 -m http.server 8731 --bind 192.168.1.3 --directory /tmp/light-switch'` in the background. The image holds the baked Wi-Fi, broker and InfluxDB credentials, so delete the file and stop the server afterwards. Stopping the ssh session does not stop the server; find its pid with `ssh stockholm 'ss -ltnp | grep :8731'` and kill it.
4. Send `OtaUrl http://192.168.1.3:8731/light-switch.bin`, then `Upgrade 1`. Poll `Status 2` until `BuildDateTime` changes (up to about 4 minutes; do not cut power), then send `OtaUrl 1`.
5. Configure the switch. An OTA keeps the old settings, so each of these is needed after flashing from an older build. Names come first so the first Home Assistant discovery message carries them, because Home Assistant derives entity ids from the name at first discovery. The MQTT host comes last.

   ```text
   Backlog DeviceName <name>; FriendlyName1 <name>; Topic <topic>
   SwitchMode1 2
   IfxToken2 <op://Private/Tasmota Firmware Secrets/influxdb_token>
   MqttUser home
   MqttPassword2 <op://Private/6it5jydd7uzj7dxvcdkdo25icm/credential>
   Backlog SetOption103 0; SetOption104 0; MqttPort 1883; MqttHost 192.168.1.3
   ```

   - `SwitchMode1 2` is the firmware default only after a settings reset, so send it once after an OTA from an older build. The relay then follows the rocker, so the light can change state.
   - The `2` variants (`IfxToken2`, `MqttPassword2`) keep the secret out of the reply. The broker item shares its title with another item that holds a different login, so address it by id.
   - `SetOption103 0` turns MQTT TLS off and `SetOption104 0` turns retained publishing back on. Home Assistant needs retained discovery messages.
   - `Backlog` replies `{}`, and the switch can be unreachable for a few seconds afterwards.

6. Compare the new switch with the reference, the bedroom light switch (its IP is in `bedroom-light.md`). The program deletes volatile keys, so the diff should be empty:

   ```bash
   q() { printf 'user = "admin:%s"\n' "$WP" | curl -s -m 8 -K - -G --data-urlencode 'cmnd=Status 0' "http://$1/cm"; }
   norm() { jq -S 'del(.Status.DeviceName, .Status.FriendlyName, .Status.Topic, .Status.Power, .StatusSTS.POWER, .StatusSTS.Uptime, .StatusSTS.UptimeSec, .StatusSTS.Heap, .StatusSTS.LoadAvg, .StatusSTS.Time, .StatusSTS.Wifi, .StatusSTS.MqttCount, .StatusSTS.Hostname, .StatusSTS.IPAddress, .StatusSTS.Berry, .StatusSNS, .StatusTIM.UTC, .StatusTIM.Local, .StatusPRM.Uptime, .StatusPRM.StartupUTC, .StatusPRM.BootCount, .StatusPRM.BCResetTime, .StatusPRM.SaveCount, .StatusPRM.RestartReason, .StatusMEM.Heap, .StatusMEM.StackLowMark, .StatusNET, .StatusMQT.MqttClient, .StatusMQT.MqttCount, .StatusFWR.BuildDateTime, .StatusFWR.CR)'; }
   diff <(q <reference-ip> | norm) <(q <new-ip> | norm)
   ```

7. Put the device in its Home Assistant area. The REST API has no device-registry endpoint, so use the WebSocket API: send `config/device_registry/list`, pick the device whose `connections` contain `["mac", "<lowercase mac with colons>"]`, then send `config/device_registry/update` with its `device_id` and `area_id`. Do this only after the device's entities exist.
8. Verify. The broker log (`ssh stockholm "docker logs --since 10m mosquitto 2>&1 | grep -a DVES_<last six MAC characters>"`) shows `New client connected ... u'home'`. The Home Assistant entity state equals the relay. Within 6 minutes (`TelePeriod 300`) the InfluxDB `tasmota` bucket has points tagged `device=<topic>`.