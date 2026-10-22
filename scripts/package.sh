#!/bin/sh
# Builds the resource you sell: dist/my-resource (and dist/my-resource.zip when zip is installed), with
# your SunLicense API key from the environment written into settings.lua. Never commit the key.
#   SUNLICENSE_API_KEY=slk_... sh scripts/package.sh
# Upload it through Tebex's asset escrow (keymaster) so buyers can't read settings.lua.
set -eu
cd "$(dirname "$0")/.."
rm -rf dist && mkdir -p dist/my-resource
cp -R fxmanifest.lua settings.lua server lib LICENSE dist/my-resource/
url="${SUNLICENSE_URL:-https://api.sunlicense.com}"
key="${SUNLICENSE_API_KEY:-}"
case "$key$url" in *"'"*|*"\\"*) echo "SUNLICENSE_API_KEY and SUNLICENSE_URL can't contain quotes or backslashes" >&2; exit 1 ;; esac
sed -e "s|url = '[^']*'|url = '$url'|" -e "s|apiKey = '[^']*'|apiKey = '$key'|" settings.lua > dist/my-resource/settings.lua
[ -n "$key" ] || echo "Warning: no SUNLICENSE_API_KEY set: licenses can't be checked." >&2
if command -v zip >/dev/null 2>&1; then (cd dist && zip -qr my-resource.zip my-resource); fi
echo "Built dist/my-resource"
