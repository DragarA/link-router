#!/bin/zsh
# Runs unit tests. Without Xcode, SwiftPM doesn't know where the Command Line Tools
# keep Swift Testing, so point the compiler, linker, and runtime at it explicitly.
set -euo pipefail
cd "${0:A:h}"
FW="$(xcode-select -p)/Library/Developer/Frameworks"
LIB="$(xcode-select -p)/Library/Developer/usr/lib"
swift test \
  -Xswiftc -F -Xswiftc "$FW" \
  -Xlinker -F -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$LIB" "$@"
