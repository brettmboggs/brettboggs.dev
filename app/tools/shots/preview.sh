#!/bin/zsh
# Records the App Store app preview: 886 x 1920, 28 seconds, H.264.
#
#   ./tools/shots/preview.sh
#
# The app walks its own tabs under the -tour flag, so the footage is the real
# app running rather than a screen recording somebody made by hand. Recording
# starts after the app is already up, because a preview that opens on the iOS
# home screen is rejected.
#
# It has no sound. simctl does not capture the simulator's audio, and this app
# is worth hearing, so the version worth shipping is this one re-shot on a
# device with QuickTime. Apple accepts a silent preview; it is just a waste of
# the one asset that could play the rain.
set -e
DEVICE=${DEVICE:-"iPhone 17 Pro Max"}
BUNDLE=dev.brettboggs.nightjar
HERE=${0:a:h}
OUT=$HERE/out
mkdir -p $OUT

SIM=$(xcrun simctl list devices available | grep -F "$DEVICE (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[[ -z $SIM ]] && { echo "no simulator named $DEVICE"; exit 1; }

xcrun simctl terminate $SIM $BUNDLE 2>/dev/null || true
xcrun simctl launch $SIM $BUNDLE -tab tonight -plus -play -tour >/dev/null
sleep 2.6
xcrun simctl io $SIM recordVideo --codec h264 --force $OUT/raw.mov &
sleep 29
kill -INT %1 2>/dev/null || true
sleep 4

swift $HERE/transcode.swift $OUT/raw.mov $OUT/preview-6.9.mp4 28
rm -f $OUT/raw.mov
echo "wrote $OUT/preview-6.9.mp4"
