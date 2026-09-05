#!/usr/bin/env bash
#
# Build Nightjar and install it on the iPhone plugged into this Mac.
#
#   ./tools/install.sh
#
# Finds the device, works out your signing team, builds, installs and launches.
# If anything fails it prints the errors and nothing else, so they can be
# pasted straight back into the conversation.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; OFF=$'\033[0m'
LOG="$(mktemp -t nightjar-build)"

say()  { printf '%s%s%s\n' "$BOLD" "$1" "$OFF"; }
note() { printf '%s  %s%s\n' "$DIM" "$1" "$OFF"; }
die()  { printf '%s%s%s\n' "$RED" "$1" "$OFF"; exit 1; }

command -v xcodebuild >/dev/null || die "Xcode command line tools are not installed. Run: xcode-select --install"

# --- 1. Which phone? --------------------------------------------------------
say "Looking for a connected iPhone"
DEVICES_JSON="$(mktemp -t nightjar-devices)"
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null 2>&1

read -r UDID DEVICE_NAME <<<"$(python3 - "$DEVICES_JSON" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit(0)
for d in devices:
    props = d.get("deviceProperties", {})
    conn = d.get("connectionProperties", {})
    if conn.get("tunnelState") in ("connected", "available") or \
       conn.get("pairingState") == "paired":
        if "iPhone" in d.get("hardwareProperties", {}).get("deviceType", "") or \
           "iPhone" in props.get("name", ""):
            print(d["identifier"], props.get("name", "iPhone"))
            break
PY
)"

if [ -z "${UDID:-}" ]; then
    die "No paired iPhone found.
  - Plug it in with the cable and unlock it
  - Tap Trust This Computer if asked
  - Settings > Privacy & Security > Developer Mode > On, then restart the phone
  Then run this again."
fi
note "$DEVICE_NAME  ($UDID)"

# --- 2. Signing -------------------------------------------------------------
if [ ! -f Local.xcconfig ]; then
    say "No signing identity configured, looking one up"
    # Prefer the team Xcode already saved into the project (set in its Signing
    # pane), then fall back to the first development certificate on the Mac.
    TEAM="$(grep -o 'DEVELOPMENT_TEAM = [A-Z0-9]*' Nightjar.xcodeproj/project.pbxproj 2>/dev/null | head -1 | awk '{print $3}')"
    [ -n "$TEAM" ] || TEAM="$(security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/.*"Apple Development: .*(\([A-Z0-9][A-Z0-9]*\))".*/\1/p' \
            | head -1)"
    if [ -z "$TEAM" ]; then
        die "Could not find an Apple Development certificate.
  Open Xcode > Settings > Accounts, sign in with your Apple ID, then run this again."
    fi
    printf 'DEVELOPMENT_TEAM = %s\n' "$TEAM" > Local.xcconfig
    note "wrote Local.xcconfig with team $TEAM (gitignored, stays on this Mac)"
else
    note "using the team in Local.xcconfig"
fi

# --- 3. Regenerate, so a fresh pull is always consistent ---------------------
python3 tools/make_project.py >/dev/null || die "Could not generate the Xcode project."

# --- 4. Build ---------------------------------------------------------------
say "Building"
note "first build takes a few minutes"
xcodebuild \
    -project Nightjar.xcodeproj \
    -scheme Nightjar \
    -configuration Debug \
    -destination "id=$UDID" \
    -derivedDataPath build \
    -allowProvisioningUpdates \
    build >"$LOG" 2>&1

if [ $? -ne 0 ]; then
    printf '\n%sBuild failed. Everything below is what went wrong:%s\n\n' "$RED" "$OFF"
    grep -E "error:|error MT|Signing for|requires a development team|Provisioning profile|No profiles|not supported|Command .* failed" "$LOG" \
        | sed 's|'"$PWD"'/||g' | sort -u | head -40
    if grep -q "No Account for Team" "$LOG"; then
        printf '\n%sThe team in Local.xcconfig is not one Xcode is signed in to. Delete Local.xcconfig, open the project in Xcode, set Team under Signing & Capabilities, build once with ⌘R, then run this again.%s\n' "$DIM" "$OFF"
    fi
    printf '\n%sFull log: %s%s\n' "$DIM" "$LOG" "$OFF"
    printf '%sPaste the lines above back into the conversation.%s\n' "$DIM" "$OFF"
    exit 1
fi

APP="$(find build/Build/Products -name 'Nightjar.app' -maxdepth 3 | head -1)"
[ -n "$APP" ] || die "Built, but Nightjar.app is not where expected. Log: $LOG"

# --- 5. Install and launch --------------------------------------------------
say "Installing on $DEVICE_NAME"
if ! xcrun devicectl device install app --device "$UDID" "$APP" >>"$LOG" 2>&1; then
    printf '%sInstall failed:%s\n\n' "$RED" "$OFF"
    tail -25 "$LOG"
    exit 1
fi

xcrun devicectl device process launch --device "$UDID" dev.brettboggs.nightjar >>"$LOG" 2>&1

printf '\n%sNightjar is on %s.%s\n' "$GREEN" "$DEVICE_NAME" "$OFF"
note "If it will not open: Settings > General > VPN & Device Management > trust your Apple ID, then tap the icon."
