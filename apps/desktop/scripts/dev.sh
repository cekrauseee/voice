#!/bin/bash
# Builds the app, runs it, and prints its log until it quits or this script is interrupted.
set -eu
cd "$(dirname "$0")/.."

scripts/bundle.sh debug

quit() {
  osascript -e 'quit app id "eu.cekrause.voice"' >/dev/null 2>&1 || true
}

quit
# The app's log, reduced to the time and the message.
log stream --level info --style compact --predicate 'subsystem == "eu.cekrause.voice"' \
  > >(sed -lnE 's/^[0-9-]+ ([0-9:]+)\.[0-9]+ +[A-Za-z]+ +Voice\[[^]]*\] \[[^]]*\] /\1  /p') &
logs=$!
trap 'quit; kill "$logs" 2>/dev/null' EXIT
trap 'exit 130' INT TERM

echo "Running Voice. It lives in the menu bar."
open -W build/Voice.app &
wait $!
