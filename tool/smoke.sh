#!/usr/bin/env bash
# Installs the APK on the running emulator, starts the game, plays a little and fails if the
# process died or the engine reported script errors.
set -u
PKG=com.rollinglegends.game
APK=$(ls apk/*.apk | head -1)
mkdir -p smoke
adb install -r "$APK" || { echo "SMOKE FAILED: install"; exit 1; }
adb logcat -c
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
SIZE=$(adb shell wm size | tr -d '\r' | awk '{print $3}')
W=${SIZE%x*}; H=${SIZE#*x}
tap() { adb shell input tap $(( W * $1 / 100 )) $(( H * $2 / 100 )); }
shot() { adb exec-out screencap -p > "smoke/$1.png" || true; }
alive() { if [ -z "$(adb shell pidof $PKG | tr -d '\r')" ]; then echo "SMOKE FAILED: not running at: $1"; adb logcat -d > smoke/logcat.txt; exit 1; fi; }

sleep 25; shot 1_start; alive "start"
# A consent form or nothing may be on top; the menu's Play button is at the bottom.
for y in 80 78 82; do tap 50 $y; sleep 2; done
sleep 4; shot 2_level; alive "level start"
adb shell input swipe $(( W / 2 )) $(( H * 60 / 100 )) $(( W * 70 / 100 )) $(( H * 60 / 100 )) 600
sleep 1; shot 3_steer_right
adb shell input swipe $(( W / 2 )) $(( H * 60 / 100 )) $(( W * 30 / 100 )) $(( H * 60 / 100 )) 600
sleep 6; shot 4_later; alive "playing"
sleep 8; shot 5_end
adb shell input keyevent KEYCODE_BACK; sleep 2; shot 6_back
adb shell input keyevent KEYCODE_HOME; sleep 3
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 5; shot 7_resumed; alive "resume"

adb logcat -d > smoke/logcat.txt
grep -E " godot +:" smoke/logcat.txt | cut -c34- | awk '!seen[$0]++' > smoke/godot_log.txt || true
grep -E "SCRIPT ERROR|FATAL EXCEPTION" smoke/logcat.txt | head -60 > smoke/errors.txt || true
grep -A1 "SCRIPT ERROR" smoke/godot_log.txt | head -40 >> smoke/errors.txt || true
echo "---- errors ----"; cat smoke/errors.txt
if grep -q "SCRIPT ERROR" smoke/errors.txt; then echo "SMOKE FAILED: script errors"; exit 1; fi
if grep -q "FATAL EXCEPTION" smoke/errors.txt && grep -q "$PKG" smoke/errors.txt; then echo "SMOKE FAILED: crash"; exit 1; fi
echo "SMOKE OK"
