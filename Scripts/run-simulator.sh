#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

device_name='Android Find · iPhone 17'
device_id=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["name"] == "Android Find · iPhone 17":
            print(device["udid"])
            raise SystemExit
')
if [ -z "$device_id" ]; then
    device_id=$(xcrun simctl create "$device_name" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
fi
device_state=$(xcrun simctl list devices --json | python3 -c '
import json, sys
identifier = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["udid"] == identifier:
            print(device["state"])
' "$device_id")
if [ "$device_state" != Booted ]; then xcrun simctl boot "$device_id"; fi
xcrun simctl bootstatus "$device_id" -b
mkdir -p Artifacts
xcodebuild -project AndroidFind.xcodeproj -scheme AndroidFind \
    -configuration Debug -sdk iphonesimulator \
    -destination "platform=iOS Simulator,id=$device_id" \
    -derivedDataPath .build build > Artifacts/build.log 2>&1
xcrun simctl install "$device_id" .build/Build/Products/Debug-iphonesimulator/AndroidFind.app
xcrun simctl launch --terminate-running-process "$device_id" dev.ryuya.AndroidFind "$@"

developer_dir=$(xcode-select -p)
device_hub="${developer_dir%/Developer}/Applications/DeviceHub.app"
simulator_app="$developer_dir/Applications/Simulator.app"
if [ -d "$device_hub" ]; then
    open "$device_hub"
elif [ -d "$simulator_app" ]; then
    open "$simulator_app"
fi
