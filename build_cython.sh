#!/bin/sh
# Compile whattheflux_core.py and whattheflux_web.py to native .so binaries using Cython.
# Run this script on the GX device itself after installation.

APP_DIR="/data/whattheflux"
cd "$APP_DIR" || exit 1

echo ""
echo "=========================================="
echo " Ancilux - Cython build"
echo "=========================================="
echo ""

# Ensure Cython is available
if ! python3 -c "import Cython" 2>/dev/null; then
    echo "Cython not found — attempting to install..."

    # Try opkg first (Venus OS / OpenEmbedded)
    if which opkg > /dev/null 2>&1; then
        opkg update -q 2>/dev/null || true
        if opkg install python3-cython 2>/dev/null; then
            echo "  Cython installed via opkg."
        fi
    fi

    # Try pip3 / pip if opkg did not work
    if ! python3 -c "import Cython" 2>/dev/null; then
        PIP=""
        if which pip3 > /dev/null 2>&1; then PIP="pip3"
        elif which pip  > /dev/null 2>&1; then PIP="pip"
        fi

        if [ -n "$PIP" ]; then
            $PIP install cython --quiet 2>/dev/null && echo "  Cython installed via $PIP."
        fi
    fi

    # Last resort: bootstrap pip via get-pip.py then install Cython
    if ! python3 -c "import Cython" 2>/dev/null; then
        echo "  Trying get-pip.py bootstrap..."
        wget -q https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py && \
            python3 /tmp/get-pip.py --quiet 2>/dev/null && \
            python3 -m pip install cython --quiet 2>/dev/null && \
            echo "  Cython installed via bootstrapped pip."
    fi

    if ! python3 -c "import Cython" 2>/dev/null; then
        echo "ERROR: could not install Cython."
        echo "       Run manually:  opkg install python3-cython"
        echo "       or:            pip3 install cython"
        exit 1
    fi
fi

# gcc is required to compile C extensions
if ! which gcc > /dev/null 2>&1; then
    echo "ERROR: gcc not found."
    echo "       Run manually:  opkg install gcc"
    exit 1
fi

echo "Compiling whattheflux_core.py..."
python3 setup.py build_ext --inplace --quiet 2>&1 | grep -v "^running\|^gcc\|^creating"

# Check compilation succeeded
if ls whattheflux_core.cpython*.so 2>/dev/null | grep -q .; then
    echo "  whattheflux_core.so compiled OK"
else
    echo "ERROR: compilation of whattheflux_core failed."
    exit 1
fi

if ls whattheflux_web.cpython*.so 2>/dev/null | grep -q .; then
    echo "  whattheflux_web.so compiled OK"
else
    echo "ERROR: compilation of whattheflux_web failed."
    exit 1
fi

# Remove source files and build artifacts
echo "Removing source files..."
rm -f whattheflux_core.py whattheflux_web.py
rm -f whattheflux_core.c whattheflux_web.c
rm -rf build/

echo ""
echo "=========================================="
echo " Build complete. Source files removed."
echo "=========================================="
echo ""
echo "Restart services to load compiled modules:"
echo "  svc -t /service/whattheflux"
echo "  svc -t /service/whattheflux-webgui"
echo ""
