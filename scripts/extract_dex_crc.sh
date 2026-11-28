#!/bin/bash
# Run after building release APK
# Usage: ./scripts/extract_dex_crc.sh mobile/build/outputs/apk/release/mobile-release.apk

APK_PATH=$1
if [ -z "$APK_PATH" ]; then
    echo "Usage: $0 <path-to-release-apk>"
    exit 1
fi

echo "DEX CRC values for: $APK_PATH"
echo "================================"
unzip -v "$APK_PATH" "classes*.dex" | grep "classes" | while read -r line; do
    crc=$(echo "$line" | awk '{print $7}')
    name=$(echo "$line" | awk '{print $8}')
    echo "$name -> CRC: $crc (0x$crc)"
done
echo ""
first_crc=$(unzip -v "$APK_PATH" "classes.dex" | grep "classes.dex" | awk '{print $7}' | head -n 1)
if [ -n "$first_crc" ]; then
    echo "Set single-dex fallback in gradle.properties:"
    echo "  EXPECTED_DEX_CRC=0x${first_crc}"
fi

echo "Set multi-dex map in gradle.properties (recommended):"
map_line=$(unzip -v "$APK_PATH" "classes*.dex" | grep "classes" | awk '{print $8":0x"$7}' | paste -sd "," -)
echo "  EXPECTED_DEX_CRC_MAP=${map_line}"
