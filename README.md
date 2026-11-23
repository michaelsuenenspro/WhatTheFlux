# WhatTheFlux Driver

Advanced Alfen EV charger integration for Victron Venus OS.

This project provides a native Victron-compatible EV charger service for Alfen chargers using Modbus TCP, with a built-in web GUI for easy configuration.

## Features

- Native Venus OS EV charger integration (VRM compatible)
- Automatic solar surplus charging with EV consumption compensation
- **Bidirectional current ramp** — current follows available surplus up and down smoothly
- **Soft ramp-up on start** — begins at minimum current to prevent inrush trips
- **Smart ramp-to-stop** — reduces current gradually; holds at lower level if surplus stabilises
- Automatic 1-phase / 3-phase switching with debounce **and sustained confirmation** — no oscillation at sunrise/sunset
- Cooldown timer after a stop to prevent rapid cycling
- Noise filtering on protection checks (rolling average over 15 s)
- Manual, automatic and scheduled charging modes
- Day-of-week scheduling (e.g. weekdays only)
- EV priority mode with battery reserve
- Battery protection logic (SOC, soft and hard discharge limits)
- Grid import protection
- Live config reload without driver restart
- Web GUI for live status and settings (port 8080)
- License status shown in web GUI and VRM alarms
- Structured logging with rotation
- pymodbus 2.x and 3.x compatible
- SIGTERM handler (sets current to 0A on shutdown)

---

## Requirements

**Victron side:**
- Victron Venus OS (Cerbo GX, NanoPi, Raspberry Pi, etc.)
- Python 3 (included in Venus OS)
- pymodbus (included in Venus OS)

**Alfen side:**
- Alfen charger with **Load Balancing license** (required for Modbus TCP access)
- **Modbus TCP Smart Charging** enabled in Alfen ACE app
- **Safe Current / Offline Current** set to **0A** in Alfen ACE app

> **Important:** If Safe Current is not set to 0A, the Alfen will continue charging at that current when it receives a 0A stop command from this driver (e.g. during battery protection or low surplus conditions).

**Network:**
- Alfen charger reachable from the GX device via TCP port 502

---

## Installation

SSH into your Venus OS device and run:

```bash
wget -q https://raw.githubusercontent.com/michaelsuenenspro/WhatTheFlux/main/install.sh -O /tmp/install.sh
sh /tmp/install.sh
```

The installer will ask for:
- Alfen IP address
- Device instance (default: 42)
- Maximum charging current (default: 23A)
- Minimum battery SOC (default: 30%)
- Whether to install the web GUI (port 8080)

After installation, the installer displays your **GX serial number**. You will need this to request a license.

---

## License

This driver requires a valid license file tied to your GX device.

**Step 1** — Note your GX serial number (shown at the end of installation, or run):
```bash
cat /data/venus/unique-id
```

**Step 2** — Contact Ancilux Services with your serial number:
```
info@ancilux.be
```

**Step 3** — Place the received `license.lic` file on the GX:
```bash
scp license.lic root@<gx-ip>:/data/whattheflux/license.lic
svc -t /service/whattheflux
```

The driver will not start without a valid license. License status is visible in the web GUI and as a VRM alarm (`/Alarms/License`).

---

## Web GUI

After installation, open your browser and go to:

```
http://<gx-ip>:8080
```

The web GUI shows:
- Live status: power, current, phases, grid, battery, SOC, PV
- License status: serial, expiry date, validity
- All settings with instant apply via **Save & Reload** (no restart needed)

---

## Operating Modes

| Mode | Description |
|------|-------------|
| 0 | Manual — the configured current is the most taken from the grid; any solar surplus is added on top (up to `max_current`). With `manual_grid_only` the grid share really comes from the grid, not the home battery |
| 1 | Automatic — charges on solar surplus only |
| 2 | Scheduled — charges within configured time window and days |

---

## EV Priority

| Value | Description |
|-------|-------------|
| 0 | Battery priority — only surplus after battery is charged |
| 1 | EV priority — uses battery above reserve threshold |

In **battery priority** mode, available power = solar grid export only. The `grid_import_limit_w` protection is active: charging stops if the grid starts importing.

In **EV priority** mode, available power = solar grid export + battery power above `battery_reserve_charge_w`. The bidirectional ramp naturally prevents grid import: if the grid starts importing, available power drops and the ramp reduces the charging current automatically. The explicit `grid_import_limit_w` check is therefore skipped in EV priority mode — a hard stop and 60 s cooldown would be counterproductive.

---

## Automatic Mode — How It Works

In automatic mode the driver continuously calculates the available power and adjusts the charging current every 5 seconds:

- **Starting**: charging begins when surplus exceeds `export_start_w` (default 1400 W) and the cooldown has expired. Current starts at `min_current` (6 A) and ramps up by `ramp_step_a` (2 A) per cycle.
- **Running**: current tracks the available power up and down smoothly using the bidirectional ramp.
- **Surplus drops**: current ramps down by `ramp_down_step_a` (4 A) per cycle toward the new lower level. If surplus stabilises above the minimum, charging continues at the lower current — no unnecessary stop.
- **Stopping**: charging stops (with cooldown) only when available power can no longer sustain `min_current` (default 6 A × 230 V = 1380 W). Hard protection stops (battery, SOC) cut immediately.
- **Grid import** (battery priority only): if grid import exceeds `grid_import_limit_w` for 15 s, charging stops with cooldown.

---

## Configuration

Configuration file: `/data/whattheflux/config.ini`

After editing, either use **Save & Reload** in the web GUI or restart the driver:
```bash
svc -t /service/whattheflux
```

Key settings:

| Section | Key | Default | Description |
|---------|-----|---------|-------------|
| `auto` | `export_start_w` | 1400 | Minimum surplus to start charging (from idle) |
| `auto` | `ramp_step_a` | 2.0 | Current increase per 5 s cycle during ramp-up (A) |
| `auto` | `ramp_down_step_a` | 4.0 | Current decrease per 5 s cycle during ramp-down (A) |
| `auto` | `phase3_start_w` | 5000 | Switch to 3-phase above this surplus |
| `auto` | `phase3_stop_w` | 3800 | Switch back to 1-phase below this |
| `auto` | `stop_cooldown_s` | 60 | Seconds to wait after a stop before restarting |
| `auto` | `soc_min` | 30 | Minimum battery SOC — stops at or below |
| `auto` | `battery_discharge_limit_w` | -200 | Soft discharge stop (averaged over 15 s) |
| `auto` | `battery_hard_discharge_w` | -800 | Hard discharge limit. While charging above the minimum, the car is first cut to what the sun still covers (one phase if three no longer fit); it stops only at the minimum or after `battery_hard_discharge_cycles` samples in a row |
| `auto` | `battery_hard_discharge_cycles` | 3 | Samples in a row below `battery_hard_discharge_w` before a hard stop |
| `auto` | `grid_import_limit_w` | 200 | Grid import limit — battery priority mode only (averaged over 15 s). The car is cut back first and only stopped if even the minimum on one phase is too much |
| `auto` | `phase_switch_debounce_s` | 120 | Minimum seconds between phase switches |
| `auto` | `phase_switch_confirm_cycles` | 3 | Consecutive cycles above/below threshold before switching phase (3 × 5 s = 15 s) |
| `auto` | `ramp_settle_cycles` | 6 | Cycles of active charging before battery power counts in EV priority available power (6 × 5 s = 30 s) |
| `auto` | `phase_switch_grace_s` | 20 | Seconds after a phase switch during which charging is not stopped or raised while the car resumes |
| `auto` | `phase_up_confirm_s` | 60 | The surplus must stay above `phase3_start_w` this long before switching from 1 to 3 phases. Switching down is immediate |
| `auto` | `phase_upshift_hold_s` | 300 | No upshift for this long after a downshift. Each further downshift within the hour doubles it, so a day of passing clouds settles on one phase |
| `auto` | `phase_upshift_hold_max_s` | 1800 | Upper limit for that hold-off |
| `charging` | `min_current` | 6 | Minimum charging current (A) |
| `charging` | `max_current` | 23 | Maximum charging current (A) — applies to both phases |
| `charging` | `max_current_1p` | 25 | Hard cable safety limit for 1-phase (A) — cannot be exceeded regardless of other settings |
| `charging` | `manual_grid_only` | true | Manual mode: raise the ESS grid setpoint by the EV's grid share while charging, so ESS imports it instead of discharging the home battery into the car. The original setpoint is restored afterwards, also after a crash |
| `schedule` | `start_hour` | 22 | Hour to start scheduled charging |
| `schedule` | `end_hour` | 6 | Hour to stop scheduled charging |
| `schedule` | `days` | 0,1,2,3,4,5,6 | Active days (0=Mon … 6=Sun) |

---

## Useful Commands

```bash
# Set mode
dbus -y com.victronenergy.evcharger.whattheflux_42 /Mode SetValue 1   # auto
dbus -y com.victronenergy.evcharger.whattheflux_42 /Mode SetValue 0   # manual
dbus -y com.victronenergy.evcharger.whattheflux_42 /Mode SetValue 2   # scheduled

# EV priority
dbus -y com.victronenergy.evcharger.whattheflux_42 /EvPriority SetValue 1  # EV first
dbus -y com.victronenergy.evcharger.whattheflux_42 /EvPriority SetValue 0  # battery first

# Start / stop
dbus -y com.victronenergy.evcharger.whattheflux_42 /StartStop SetValue 1
dbus -y com.victronenergy.evcharger.whattheflux_42 /StartStop SetValue 0

# Live debug
dbus -y com.victronenergy.evcharger.whattheflux_42 /Debug/Reason GetValue

# Alarm status (0=ok, 1=warning, 2=alarm)
dbus -y com.victronenergy.evcharger.whattheflux_42 /Alarms/Failure GetValue
dbus -y com.victronenergy.evcharger.whattheflux_42 /Alarms/License GetValue

# Logs
tail -f /var/log/whattheflux.log
```

---

## Uninstall

```bash
sh /data/whattheflux/uninstall.sh
```

---

## Disclaimer

Use at your own risk. This project is not affiliated with Victron Energy or Alfen.
