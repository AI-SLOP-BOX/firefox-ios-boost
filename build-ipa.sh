#!/bin/sh
# build-ipa.sh — Rebuild the Fennec device IPA in one command.
#
# Handles the local-only quirks so you don't have to:
#   1. Re-applies the nimbus-fml.sh space-in-path fix (that file is
#      gitignored and re-downloaded by bootstrap.sh, so the fix is
#      re-applied idempotently on every run).
#   2. Temporarily neuters the SwiftLint build phase (upstream's own
#      tree fails strict lint; reverted automatically on exit).
#   3. Builds Fennec for generic iOS device, unsigned.
#   4. Packages ~/Desktop/FirefoxBoost-unsigned.ipa for sideloading
#      (Sideloadly / AltStore re-sign it with your Apple ID).
#
# Usage: ./build-ipa.sh
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
PBX_REL="firefox-ios/Client.xcodeproj/project.pbxproj"
PBX="$ROOT/$PBX_REL"
NIMBUS="$ROOT/firefox-ios/bin/nimbus-fml.sh"
IPA="$HOME/Desktop/FirefoxBoost-unsigned.ipa"

revert_pbx() {
    git -C "$ROOT" checkout -- "$PBX_REL" 2>/dev/null || true
}
trap revert_pbx EXIT INT TERM

# 1. nimbus-fml.sh: eval-based runner breaks when the repo path contains
#    spaces. Rewrite it to direct exec (idempotent: skipped when the
#    eval line is already gone).
if [ -f "$NIMBUS" ] && grep -q 'eval "$CMD"' "$NIMBUS"; then
    echo "Patching nimbus-fml.sh for space-in-path (local only)..."
    python3 - "$NIMBUS" <<'PYEOF'
import sys
p = sys.argv[1]
data = open(p).read()
old_fn = ('echo_eval() {\n'
           '    local CMD="$*"\n'
           '    # Truncating the absolute paths into something easier to read.\n'
           '    local display=${CMD//"$SOURCE_ROOT"/\\$SOURCE_ROOT}\n'
           '    echo "$display"\n'
           '    eval "$CMD"\n'
           '}')
assert data.count(old_fn) == 1
new_fn = ('echo_eval() {\n'
          '    # SPACE_PATH_FIX: direct exec instead of eval so repo paths\n'
          '    # containing spaces survive (local-only patch).\n'
          '    local display="$*"\n'
          '    display=${display//"$SOURCE_ROOT"/\\$SOURCE_ROOT}\n'
          '    echo "$display"\n'
          '    "$@"\n'
          '}')
data = data.replace(old_fn, new_fn)
old_v = 'echo_eval "$BINARY_PATH validate $repo_args --cache-dir $CACHE_DIR $APP_FML_FILE"'
assert data.count(old_v) == 1
data = data.replace(old_v, 'echo_eval "$BINARY_PATH" validate $repo_args --cache-dir "$CACHE_DIR" "$APP_FML_FILE"')
old_g = 'echo_eval "$BINARY_PATH generate $repo_args --channel $CHANNEL --language swift --cache-dir $CACHE_DIR $input_pattern $output_dir"'
assert data.count(old_g) == 1
data = data.replace(old_g, 'echo_eval "$BINARY_PATH" generate $repo_args --channel "$CHANNEL" --language swift --cache-dir "$CACHE_DIR" "$input_pattern" "$output_dir"')
open(p, 'w').write(data)
print("nimbus-fml.sh patched")
PYEOF
    sh -n "$NIMBUS" || exit 1
fi

# 2. Neuter the SwiftLint build phase for this run only (trap reverts).
python3 - "$PBX" <<'PYEOF'
import sys
p = sys.argv[1]
data = open(p).read()
old = 'shellScript = "SWIFTLINT_ROOT='
assert data.count(old) == 1
data = data.replace(old, 'shellScript = "exit 0\\nSWIFTLINT_ROOT=')
open(p, 'w').write(data)
print("SwiftLint phase skipped for this build")
PYEOF

# 3. Build.
xcodebuild build \
    -project "$ROOT/firefox-ios/Client.xcodeproj" \
    -scheme Fennec \
    -destination 'generic/platform=iOS' \
    CODE_SIGNING_ALLOWED=NO \
    -skipMacroValidation || exit 1

# 4. Package.
APP=$(ls -dt "$HOME/Library/Developer/Xcode/DerivedData/Client-"*/Build/Products/Debug-iphoneos/Client.app 2>/dev/null | head -1)
[ -n "$APP" ] || { echo "Client.app not found"; exit 1; }
rm -rf /tmp/fx_ipapack && mkdir -p /tmp/fx_ipapack/Payload
cp -R "$APP" /tmp/fx_ipapack/Payload/
ditto -c -k --sequesterRsrc --keepParent /tmp/fx_ipapack/Payload "$IPA"
rm -rf /tmp/fx_ipapack
echo "Done: $IPA"
