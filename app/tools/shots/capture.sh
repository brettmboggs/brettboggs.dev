#!/bin/zsh
# Captures every screen the store listing uses, from a simulator, at the exact
# 6.9 inch size the App Store wants (1320 x 2868). Nothing here is manual, so
# the set can be rebuilt after any change to the app.
#
#   ./tools/shots/capture.sh            # build, seed, shoot into tools/shots/raw
#
# The app reads the -tab / -sheet / -plus / -play flags only in a DEBUG build.
# See Nightjar/Support/Demo.swift.
set -e
DEVICE=${DEVICE:-"iPhone 17 Pro Max"}
BUNDLE=dev.brettboggs.nightjar
HERE=${0:a:h}
RAW=$HERE/raw
DD=${DD:-$HERE/.build}
mkdir -p $RAW

SIM=$(xcrun simctl list devices available | grep -F "$DEVICE (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[[ -z $SIM ]] && { echo "no simulator named $DEVICE"; exit 1; }
xcrun simctl boot $SIM 2>/dev/null || true
xcrun simctl bootstatus $SIM -b >/dev/null

cd ${0:a:h}/../..
python3 tools/make_project.py >/dev/null
xcodebuild build -project Nightjar.xcodeproj -scheme Nightjar -configuration Debug \
  -destination "id=$SIM" -derivedDataPath $DD CODE_SIGNING_ALLOWED=NO > $DD.log 2>&1 \
  || { echo "build failed"; grep -E "error:" $DD.log | head; exit 1; }
xcrun simctl install $SIM $DD/Build/Products/Debug-iphonesimulator/Nightjar.app

python3 tools/shots/seed.py "$(xcrun simctl get_app_container $SIM $BUNDLE data)"

shoot () {   # shoot <name> <launch args...>
  local name=$1; shift
  xcrun simctl terminate $SIM $BUNDLE 2>/dev/null || true
  xcrun simctl launch $SIM $BUNDLE "$@" >/dev/null
  sleep 6
  xcrun simctl io $SIM screenshot $RAW/$name.png >/dev/null 2>&1
  echo "  $name"
}

echo "shooting into $RAW"
shoot tonight  -tab tonight -plus -play
shoot breathe  -tab breathe -plus
shoot sounds   -tab sounds  -plus -play
shoot routine  -tab tonight -sheet routine -plus
shoot wake     -tab rest    -sheet wake -plus
shoot rest     -tab rest    -plus
shoot bedside  -tab tonight -sheet bedside -plus
shoot settings -sheet settings -plus
echo "now: python3 tools/shots/compose.py"
