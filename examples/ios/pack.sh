#!/usr/bin/env bash
# wrap an iOS executable + Info.plist (+ optional resources) into an .app.
# simulator: ad-hoc sign. device: --identity and --profile.
set -euo pipefail

usage() {
    echo "usage: $0 <binary> [--resources DIR] [--out DIR] [--identity NAME] [--profile PATH]" >&2
    echo "  simulator: $0 examples/ecobuild/pbr --resources examples/pbr/resources" >&2
    echo "  device:    $0 examples/ecobuild/pbr --resources examples/pbr/resources \\" >&2
    echo "               --identity 'Apple Development: Name (ID)' --profile path.mobileprovision" >&2
    exit 2
}

if [ $# -lt 1 ]; then
    usage
fi

binary=""
resources=""
out="var/Visu.app"
identity=""
profile=""

while [ $# -gt 0 ]; do
    case "$1" in
        --resources)
            shift
            resources="${1:-}"
            [ -n "$resources" ] || usage
            ;;
        --out)
            shift
            out="${1:-}"
            [ -n "$out" ] || usage
            ;;
        --identity)
            shift
            identity="${1:-}"
            [ -n "$identity" ] || usage
            ;;
        --profile)
            shift
            profile="${1:-}"
            [ -n "$profile" ] || usage
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -n "$binary" ]; then
                usage
            fi
            binary="$1"
            ;;
    esac
    shift
done

[ -n "$binary" ] || usage
[ -f "$binary" ] || { echo "pack: no binary at $binary" >&2; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"
plist="$here/Info.plist"
[ -f "$plist" ] || { echo "pack: missing $plist" >&2; exit 1; }

name="$(basename "$binary")"
rm -rf "$out"
mkdir -p "$out"
cp "$binary" "$out/$name"
# rewrite CFBundleExecutable to this binary's name
sed "s#<string>ios</string>#<string>${name}</string>#" "$plist" > "$out/Info.plist"

if [ -n "$resources" ]; then
    [ -d "$resources" ] || { echo "pack: no resources dir $resources" >&2; exit 1; }
    # copy into the .app root — a folder named resources is Resources on
    # APFS and codesign then rejects the bundle
    cp -R -X "$resources/." "$out/"
fi

xattr -cr "$out" >/dev/null 2>&1 || true

if [ -n "$identity" ]; then
    [ -n "$profile" ] || { echo "pack: --identity needs --profile" >&2; exit 1; }
    [ -f "$profile" ] || { echo "pack: no profile at $profile" >&2; exit 1; }
    cp "$profile" "$out/embedded.mobileprovision"
    ents="$(mktemp -t visu-ents.XXXXXX.plist)"
    security cms -D -i "$profile" \
        | plutil -extract Entitlements xml1 -o "$ents" -
    codesign -s "$identity" --force --generate-entitlement-der \
        --entitlements "$ents" "$out"
    rm -f "$ents"
else
    codesign -s - --force "$out" >/dev/null
fi
echo "packed $out ($name)"
