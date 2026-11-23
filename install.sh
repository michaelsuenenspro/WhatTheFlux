#!/bin/sh

APP_DIR="/data/whattheflux"
SERVICE_DIR="/service/whattheflux"
WEBGUI_SERVICE_DIR="/service/whattheflux-webgui"
GITHUB_RAW="https://raw.githubusercontent.com/michaelsuenenspro/WhatTheFlux/main"
GITHUB_RELEASE="https://github.com/michaelsuenenspro/WhatTheFlux/releases/latest/download"

echo ""
echo "=========================================="
echo " WhatTheFlux Installer v2"
echo "       Ancilux Services"
echo "=========================================="
echo ""

# --- Input ---

read -p "Alfen IP address: " ALFEN_IP
if [ -z "$ALFEN_IP" ]; then
    echo "ERROR: IP address is required."
    exit 1
fi

read -p "Device instance [42]: " DEVICE_INSTANCE
DEVICE_INSTANCE=${DEVICE_INSTANCE:-42}

read -p "Maximum charging current in Ampere [23]: " MAX_CURRENT
MAX_CURRENT=${MAX_CURRENT:-23}

read -p "Minimum battery SOC % [30]: " SOC_MIN
SOC_MIN=${SOC_MIN:-30}

read -p "Install web GUI on port 8080? [Y/n]: " INSTALL_WEBGUI
INSTALL_WEBGUI=$(echo "${INSTALL_WEBGUI:-y}" | tr '[:upper:]' '[:lower:]')

echo ""
echo "Starting installation..."
echo ""

# --- Create directories ---

mkdir -p "$APP_DIR"

# --- Helper functions ---

download_raw() {
    wget -q --show-progress -O "$APP_DIR/$2" "$GITHUB_RAW/$1" || {
        echo "ERROR: could not download $1."
        exit 1
    }
}

download_release() {
    wget -q --show-progress -O "$APP_DIR/$2" "$GITHUB_RELEASE/$1" 2>/dev/null
    return $?
}

# --- Download launcher scripts (always from raw — no logic inside) ---

echo "Downloading launcher scripts..."
download_raw "whattheflux.py" "whattheflux.py"
download_raw "run"                              "run"

if [ "$INSTALL_WEBGUI" != "n" ]; then
    download_raw "whattheflux_webgui.py"  "whattheflux_webgui.py"
    download_raw "run-webgui" "run-webgui"
fi

# --- Download the compiled binaries for this device ---

echo ""
echo "Downloading compiled binaries..."
EXT=$(python3 -c "import sysconfig; print(sysconfig.get_config_var('EXT_SUFFIX') or '')")

download_release "whattheflux_core$EXT" "whattheflux_core$EXT" || {
    rm -f "$APP_DIR/whattheflux_core$EXT"
    echo "ERROR: no release binary for this device (whattheflux_core$EXT)."
    echo "       Please report this file name to info@ancilux.be."
    exit 1
}
echo "  whattheflux_core downloaded"

if [ "$INSTALL_WEBGUI" != "n" ]; then
    download_release "whattheflux_web$EXT" "whattheflux_web$EXT" || {
        rm -f "$APP_DIR/whattheflux_web$EXT"
        echo "ERROR: could not download the web GUI binary (whattheflux_web$EXT)."
        exit 1
    }
    echo "  whattheflux_web downloaded"
fi

# --- Write config ---

echo ""
echo "Writing configuration..."

if [ -f "$APP_DIR/config.ini" ]; then
    echo "Existing config.ini found — keeping it unchanged."
else
cat > "$APP_DIR/config.ini" <<EOF
[alfen]
ip = $ALFEN_IP
port = 502
unit_id = 1

[venus]
device_instance = $DEVICE_INSTANCE
custom_name = WhatTheFlux
position = 0
poll_ms = 5000

[charging]
min_current    = 6
max_current    = $MAX_CURRENT
max_current_1p = 25
manual_current = 16
manual_phases = 3
default_mode = 1
default_ev_priority = 0
battery_reserve_charge_w = 300
manual_grid_only = true

[schedule]
current = 16
phases = 3
start_hour = 22
end_hour = 6
days = 0,1,2,3,4,5,6

[auto]
export_start_w = 1400
phase3_start_w = 5000
phase3_stop_w = 3800
grid_import_limit_w = 200
battery_discharge_limit_w = -200
battery_hard_discharge_w = -800
soc_min = $SOC_MIN
phase_switch_debounce_s      = 120
phase_switch_confirm_cycles  = 3
ramp_settle_cycles           = 6
phase_switch_grace_s         = 20
phase_up_confirm_s           = 60
phase_upshift_hold_s         = 300
phase_upshift_hold_max_s     = 1800
battery_hard_discharge_cycles = 3

[dbus_services]
pv_autodetect = true

[registers]
set_current = 1210
phase_switch = 1215

[logging]
file = /var/log/whattheflux.log
level = INFO
EOF
fi

# --- Permissions ---

echo "Setting permissions..."
chmod +x "$APP_DIR/whattheflux.py"
chmod +x "$APP_DIR/run"

# --- Driver service ---

echo "Creating driver service..."
if [ -L "$SERVICE_DIR" ]; then
    svc -d "$SERVICE_DIR" 2>/dev/null
    rm -f "$SERVICE_DIR"
fi
ln -s "$APP_DIR" "$SERVICE_DIR"
sleep 1
svc -u "$SERVICE_DIR"

# --- Persist service symlink across reboots via rc.local ---

RC_LOCAL="/data/rc.local"
RCLINE_DRIVER="ln -sf $APP_DIR $SERVICE_DIR"

if [ ! -f "$RC_LOCAL" ]; then
    echo "#!/bin/bash" > "$RC_LOCAL"
    chmod +x "$RC_LOCAL"
fi

if ! grep -qF "$RCLINE_DRIVER" "$RC_LOCAL"; then
    echo "$RCLINE_DRIVER" >> "$RC_LOCAL"
fi

# --- Web GUI service ---

if [ "$INSTALL_WEBGUI" != "n" ]; then
    chmod +x "$APP_DIR/run-webgui"
    sed -i "s/whattheflux_42/whattheflux_${DEVICE_INSTANCE}/g" "$APP_DIR/whattheflux_web.py" 2>/dev/null || true

    echo "Creating web GUI service..."
    mkdir -p "$WEBGUI_SERVICE_DIR"
    ln -sf "$APP_DIR/run-webgui" "$WEBGUI_SERVICE_DIR/run"
    sleep 1
    svc -u "$WEBGUI_SERVICE_DIR"

    RCLINE_WEBGUI="mkdir -p $WEBGUI_SERVICE_DIR && ln -sf $APP_DIR/run-webgui $WEBGUI_SERVICE_DIR/run"
    if ! grep -qF "$RCLINE_WEBGUI" "$RC_LOCAL"; then
        echo "$RCLINE_WEBGUI" >> "$RC_LOCAL"
    fi
fi

# --- Done ---

echo ""
echo "=========================================="
echo " Installation complete!"
echo "=========================================="
echo ""
echo "Check driver status:"
echo "  svstat $SERVICE_DIR"
echo ""
echo "Follow logs:"
echo "  tail -f /var/log/whattheflux.log"
echo ""

if [ "$INSTALL_WEBGUI" != "n" ]; then
    GX_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    echo "Web GUI:"
    echo "  http://${GX_IP:-<gx-ip>}:8080"
    echo ""
fi

GX_SERIAL=$(cat /data/venus/unique-id 2>/dev/null || echo "unknown")

echo "=========================================="
echo " LICENSE REQUIRED"
echo "=========================================="
echo ""
echo "This driver requires a valid license file."
echo ""
echo "Your GX serial number is: $GX_SERIAL"
echo ""
echo "Send this serial to Ancilux Services to receive your license:"
echo "  info@ancilux.be"
echo ""
echo "Once received, install the license file:"
echo "  scp license.lic root@${GX_IP:-<gx-ip>}:$APP_DIR/license.lic"
echo "  svc -t $SERVICE_DIR"
echo ""
echo "Without a license the driver will not start."
echo ""
