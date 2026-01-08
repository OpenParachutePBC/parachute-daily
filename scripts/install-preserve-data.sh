#!/bin/bash
# Install Daily app while preserving user data
# Usage: ./scripts/install-preserve-data.sh [device-id]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APK_PATH="$PROJECT_DIR/build/app/outputs/flutter-apk/app-debug.apk"

# Get device ID from argument or auto-detect
DEVICE_ID="${1:-}"

if [ -z "$DEVICE_ID" ]; then
    # Try to find a connected device
    DEVICES=$(adb devices | grep -v "List of devices" | grep -v "offline" | grep "device$" | cut -f1)
    DEVICE_COUNT=$(echo "$DEVICES" | grep -c . || true)

    if [ "$DEVICE_COUNT" -eq 0 ]; then
        echo "Error: No devices connected"
        echo "Connect a device or start an emulator, then try again"
        exit 1
    elif [ "$DEVICE_COUNT" -gt 1 ]; then
        echo "Multiple devices found. Please specify one:"
        echo "$DEVICES"
        echo ""
        echo "Usage: $0 <device-id>"
        exit 1
    else
        DEVICE_ID="$DEVICES"
    fi
fi

echo "Building debug APK..."
cd "$PROJECT_DIR"
flutter build apk --debug

echo ""
echo "Installing to device: $DEVICE_ID"
echo "Using -r flag to preserve app data..."

adb -s "$DEVICE_ID" install -r "$APK_PATH"

echo ""
echo "Done! App installed with data preserved."
