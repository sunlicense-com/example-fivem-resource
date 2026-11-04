#!/bin/sh
# Builds the resource you sell: dist/my-resource (and dist/my-resource.zip when zip is installed), with
# your SunLicense API key from the environment written into settings.lua. Never commit the key.
#   SUNLICENSE_API_KEY=slk_... SUNLICENSE_PRODUCT=my-resource sh scripts/package.sh
# Upload it through Tebex's asset escrow (keymaster) so buyers can't read settings.lua.
#
# Core unlock: with SUNLICENSE_PRODUCT (your product's code) and the sunlicense CLI signed in (or
# SUNLICENSE_TOKEN set), server/core.lua is sealed into server/core.sealed and left out of the build, so
# your features only run after a valid license check. The digests of the files in SUNLICENSE_DIGEST
# (default fxmanifest.lua) go inside it: a changed copy of those is reported to Sentinel. Digest only
# files Tebex's escrow leaves readable (fxmanifest.lua, escrow_ignore files): escrowed files change.
set -eu
cd "$(dirname "$0")/.."
rm -rf dist && mkdir -p dist/my-resource
cp -R fxmanifest.lua settings.lua server lib LICENSE dist/my-resource/
url="${SUNLICENSE_URL:-https://api.sunlicense.com}"
key="${SUNLICENSE_API_KEY:-}"
case "$key$url" in *"'"*|*"\\"*) echo "SUNLICENSE_API_KEY and SUNLICENSE_URL can't contain quotes or backslashes" >&2; exit 1 ;; esac
sed -e "s|url = '[^']*'|url = '$url'|" -e "s|apiKey = '[^']*'|apiKey = '$key'|" settings.lua > dist/my-resource/settings.lua
[ -n "$key" ] || echo "Warning: no SUNLICENSE_API_KEY set: licenses can't be checked." >&2

product="${SUNLICENSE_PRODUCT:-}"
if [ -n "$product" ]; then
    command -v sunlicense >/dev/null 2>&1 || {
        echo "SUNLICENSE_PRODUCT is set but the sunlicense CLI isn't installed: https://docs.sunlicense.com/cli/" >&2; exit 1; }
    set --
    for f in ${SUNLICENSE_DIGEST:-fxmanifest.lua}; do set -- "$@" --digest "$f"; done
    (cd dist/my-resource && sunlicense seal server/core.lua --product "$product" -o server/core.sealed "$@")
    rm dist/my-resource/server/core.lua
    echo "Sealed server/core.lua into server/core.sealed (core unlock)."
else
    echo "Note: no SUNLICENSE_PRODUCT set: server/core.lua ships as it is (no core unlock)." >&2
fi

if command -v zip >/dev/null 2>&1; then (cd dist && zip -qr my-resource.zip my-resource); fi
echo "Built dist/my-resource"
