#!/usr/bin/env python3
"""Validate the exported iPhone package before a TestFlight upload."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import zipfile

root = Path(__file__).resolve().parent.parent
ipa = Path(sys.argv[1]).resolve()
expected_build = sys.argv[2]
config_path = root / 'Distribution/AppInfo.json'
if not config_path.exists():
    raise SystemExit('Copy Distribution/Examples/AppInfo.json to Distribution/AppInfo.json and configure signing first')
app_info = json.loads(config_path.read_text())
expected_team = os.environ.get('APPLE_TEAM_ID') or app_info.get('teamId')
if not expected_team or expected_team == 'YOUR_APPLE_TEAM_ID':
    raise SystemExit('Set APPLE_TEAM_ID or teamId in the local Distribution/AppInfo.json')
private_dir = root / 'Artifacts/private'
private_dir.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='package-check-', dir=private_dir) as directory:
    with zipfile.ZipFile(ipa) as package:
        names = package.namelist()
        assert not any(
            name.lower().endswith(('.p8', '.pem', '.key'))
            or 'LastDevices.json' in name
            or '/PlugIns/' in name
            or '/Cookies/' in name
            for name in names
        ), 'Unexpected user data, credentials or test bundles in package'
        package.extractall(directory)
    apps = list((Path(directory) / 'Payload').glob('*.app'))
    assert len(apps) == 1
    app = apps[0]
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == app_info['bundleId']
    assert info['CFBundleDisplayName'] == app_info['displayName']
    assert info['CFBundleVersion'] == expected_build
    assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
    assert info['UIDeviceFamily'] == [1], 'Release must target iPhone only'
    assert info['ITSAppUsesNonExemptEncryption'] is False
    assert info.get('NSBluetoothAlwaysUsageDescription'), 'Bluetooth purpose is required for passkey permission'
    icons = info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {})
    assert icons.get('CFBundleIconName') == 'AppIcon'
    assert icons.get('CFBundleIconFiles'), 'Primary app icon is missing'
    assert (app / 'PrivacyInfo.xcprivacy').exists()
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)],
                   check=True, capture_output=True)
    signed = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)],
                            check=True, capture_output=True)
    entitlements = plistlib.loads(signed.stdout)
    assert entitlements['com.apple.developer.team-identifier'] == expected_team
    assert entitlements['application-identifier'] == expected_team + '.' + app_info['bundleId']
    assert entitlements['get-task-allow'] is False
    assert entitlements['beta-reports-active'] is True
    assert not any(b'@gmail.com' in item.read_bytes() for item in app.rglob('*') if item.is_file())
    print(json.dumps({
        'displayName': info['CFBundleDisplayName'],
        'version': info['CFBundleShortVersionString'],
        'build': info['CFBundleVersion'],
        'bundleID': info['CFBundleIdentifier'],
        'deviceFamily': info['UIDeviceFamily'],
        'teamID': entitlements['com.apple.developer.team-identifier'],
        'developmentEntitlement': entitlements['get-task-allow'],
        'betaReportsActive': entitlements['beta-reports-active'],
        'signatureVerified': True,
        'privacyManifestIncluded': True,
        'bluetoothPurposeIncluded': True,
        'primaryIcon': icons['CFBundleIconName'],
        'userDataOrCredentialFilesFound': False,
        'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(),
        'ipaBytes': ipa.stat().st_size,
    }, indent=2))
