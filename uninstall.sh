#!/bin/sh

APP_DIR="/data/whattheflux"
SERVICE_DIR="/service/whattheflux"
WEBGUI_SERVICE_DIR="/service/whattheflux-webgui"

echo ""
echo "=========================================="
echo " WhatTheFlux Uninstaller"
echo "=========================================="
echo ""

read -p "Are you sure you want to uninstall? [y/N]: " CONFIRM
CONFIRM=$(echo "${CONFIRM:-n}" | tr '[:upper:]' '[:lower:]')
if [ "$CONFIRM" != "y" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Stopping driver..."
svc -d "$SERVICE_DIR" 2>/dev/null
sleep 1
rm -f "$SERVICE_DIR"

echo "Stopping web GUI..."
svc -d "$WEBGUI_SERVICE_DIR" 2>/dev/null
sleep 1
rm -rf "$WEBGUI_SERVICE_DIR"

read -p "Also remove config.ini? [y/N]: " REMOVE_CONFIG
REMOVE_CONFIG=$(echo "${REMOVE_CONFIG:-n}" | tr '[:upper:]' '[:lower:]')

if [ "$REMOVE_CONFIG" = "y" ]; then
    rm -rf "$APP_DIR"
    echo "All files removed."
else
    rm -f "$APP_DIR/whattheflux.py"
    rm -f "$APP_DIR/whattheflux_webgui.py"
    rm -f "$APP_DIR/run"
    rm -f "$APP_DIR/run-webgui"
    echo "Code removed, config.ini kept in $APP_DIR"
fi

echo ""
echo "Uninstall complete."
echo ""
