#!/bin/sh
# Copies the repository's conversion profiles into the app's assets: Flutter
# cannot bundle files from outside the app folder. app/test/profiles_test.dart
# fails when the copies are stale.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
rm -f "$here/../app/assets/profiles/"*.json
cp "$here/../../profiles/"*.json "$here/../app/assets/profiles/"
