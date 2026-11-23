#!/bin/bash
# Cross-compile Cython .so binaries on Mac (via Docker) and publish a GitHub Release.
# Usage: bash release.sh <gx-ip> <version>
# Example: bash release.sh 192.168.1.10 v1.0.1
#
# Requirements on Mac:
#   - Docker Desktop (running, with multi-platform / QEMU support)
#   - gh CLI authenticated (brew install gh && gh auth login)
#   - SSH access to the GX (password prompt is fine)

set -e

GX_IP="${1}"
VERSION="${2}"

if [ -z "$GX_IP" ] || [ -z "$VERSION" ]; then
    echo "Usage: bash release.sh <gx-ip> <version>"
    echo "Example: bash release.sh 192.168.1.10 v1.0.1"
    exit 1
fi

LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"
GX_APP_DIR="/data/whattheflux"
DIST_DIR="$LOCAL_DIR/dist"

echo ""
echo "=========================================="
echo " Ancilux - Build & Release $VERSION"
echo "=========================================="
echo ""

# --- Detect GX architecture and Python version ---
echo "Detecting GX environment..."
GX_ARCH=$(ssh "root@$GX_IP" "uname -m")
GX_PY_VER=$(ssh "root@$GX_IP" "python3 -c 'import sys; print(\"{}.{}\".format(sys.version_info.major, sys.version_info.minor))'")

echo "  Architecture : $GX_ARCH"
echo "  Python       : $GX_PY_VER"

case "$GX_ARCH" in
    armv7l)  DOCKER_PLATFORM="linux/arm/v7" ;;
    aarch64) DOCKER_PLATFORM="linux/arm64"  ;;
    x86_64)  DOCKER_PLATFORM="linux/amd64"  ;;
    *)
        echo "ERROR: unknown GX architecture '$GX_ARCH'."
        exit 1
        ;;
esac

echo "  Docker platform: $DOCKER_PLATFORM"

# --- Revoked licences are compiled into the driver: refresh that list first ---
if [ -f "$LOCAL_DIR/generate_license.py" ]; then
    echo ""
    echo "Updating revocation list in whattheflux_core.py..."
    python3 "$LOCAL_DIR/generate_license.py" revoked --to-driver "$LOCAL_DIR/whattheflux_core.py" || {
        echo "ERROR: could not update the revocation list."
        exit 1
    }
fi

# --- Cross-compile on Mac using Docker ---
echo ""
echo "Compiling with Docker ($DOCKER_PLATFORM, Python $GX_PY_VER)..."

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR"/*.so

# Run a matching Python image, install Cython, compile, copy .so to /dist
docker run --rm \
    --platform "$DOCKER_PLATFORM" \
    -v "$LOCAL_DIR:/src" \
    -v "$DIST_DIR:/dist" \
    -w /src \
    "python:${GX_PY_VER}-slim" \
    sh -c "
        apt-get update -qq && apt-get install -y -q gcc &&
        pip install cython setuptools --quiet --disable-pip-version-check &&
        python setup.py build_ext --inplace --force 2>&1 | grep -v '^running\|^gcc\|^creating\|^copying' ;
        cp whattheflux_core*.so /dist/ 2>/dev/null || true
        cp whattheflux_web*.so  /dist/ 2>/dev/null || true
        rm -f whattheflux_core*.so whattheflux_web*.so whattheflux_core.c whattheflux_web.c
        rm -rf build/
    " || {
    echo "ERROR: Docker compilation failed."
    echo "       Make sure Docker Desktop is running and supports multi-platform builds."
    echo "       Enable via: docker run --privileged --rm tonistiigi/binfmt --install all"
    exit 1
}

# Verify we got the .so files
if ! ls "$DIST_DIR"/whattheflux_core*.so > /dev/null 2>&1; then
    echo "ERROR: whattheflux_core.so not found in dist/ after build."
    exit 1
fi
if ! ls "$DIST_DIR"/whattheflux_web*.so > /dev/null 2>&1; then
    echo "ERROR: whattheflux_web.so not found in dist/ after build."
    exit 1
fi

echo ""
echo "Compiled binaries:"
ls -lh "$DIST_DIR"/*.so

# --- Deploy launchers to GX ---
echo ""
echo "Uploading launcher scripts to GX..."
scp "$LOCAL_DIR/whattheflux.py" "root@$GX_IP:$GX_APP_DIR/whattheflux.py"
scp "$LOCAL_DIR/whattheflux_webgui.py"                        "root@$GX_IP:$GX_APP_DIR/whattheflux_webgui.py"

# --- Deploy binaries to GX ---
echo "Uploading binaries to GX..."
scp "$DIST_DIR"/whattheflux_core*.so  "root@$GX_IP:$GX_APP_DIR/"
scp "$DIST_DIR"/whattheflux_web*.so   "root@$GX_IP:$GX_APP_DIR/"

echo "Restarting services on GX..."
ssh "root@$GX_IP" "svc -t $GX_APP_DIR"

# --- Create GitHub Release ---
echo ""
echo "Creating GitHub Release $VERSION..."

gh release create "$VERSION" \
    "$DIST_DIR"/whattheflux_core*.so \
    "$DIST_DIR"/whattheflux_web*.so \
    --title "WhatTheFlux $VERSION" \
    --notes "$(cat <<NOTES
## Ancilux Services — WhatTheFlux $VERSION

Pre-compiled binary release for Victron Venus OS.

### Install

SSH into your Venus OS device and run:

\`\`\`bash
wget -q https://raw.githubusercontent.com/michaelsuenenspro/WhatTheFlux/main/install.sh -O /tmp/install.sh
sh /tmp/install.sh
\`\`\`

### Contact

info@ancilux.be
NOTES
)" || {
    echo "ERROR: GitHub release creation failed."
    echo "       Make sure 'gh' is installed and authenticated: brew install gh && gh auth login"
    exit 1
}

echo ""
echo "=========================================="
echo " Release $VERSION published on GitHub!"
echo "=========================================="
echo ""
