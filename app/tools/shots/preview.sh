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
# simctl does not capture the simulator's audio, and App Store Connect rejects
# a preview with no audio track, so the sound is rendered separately by
# mixdown.swift. That runs the app's own Renderer offline, faster than real
# time, and mux.swift lays the result onto the video without re-encoding it.
# The rain in the preview is the same rain the app makes.
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

# 8.5 MB, because some uploaders cap at ten and Apple does not mind.
swift $HERE/transcode.swift $OUT/raw.mov $OUT/silent.mp4 28 8500000
rm -f $OUT/raw.mov

# mixdown.swift has top level code, so it has to be called main.swift to build
# alongside the audio sources it needs.
BUILD=$HERE/.build/mix
mkdir -p $BUILD
cp $HERE/mixdown.swift $BUILD/main.swift
swiftc -O -o $BUILD/mixdown $BUILD/main.swift \
  Nightjar/Audio/DSP.swift Nightjar/Audio/Textures.swift \
  Nightjar/Audio/TexturesLiving.swift Nightjar/Audio/TexturesRooms.swift \
  Nightjar/Audio/TexturesWeather.swift Nightjar/Audio/BreathGuideTexture.swift \
  Nightjar/Audio/RecordingTexture.swift Nightjar/Audio/RecordingStream.swift \
  Nightjar/Audio/AudioRingBuffer.swift Nightjar/Audio/Renderer.swift \
  Nightjar/Model/SoundCatalog.swift

$BUILD/mixdown 28 $OUT/preview-audio.m4a
swift $HERE/mux.swift $OUT/silent.mp4 $OUT/preview-audio.m4a $OUT/preview-6.9.mp4
rm -f $OUT/silent.mp4 $OUT/preview-audio.m4a
echo "wrote $OUT/preview-6.9.mp4"
