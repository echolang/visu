# iOS pack

Windowed examples are iOS apps. `visu::os::run` is the OS pump
(UIApplicationMain + a display link). Host-backed apps go through
`visu::app::run(Application)` (Quickstart, fullapp). This directory
only holds the bundle plist and a pack script.

```bash
echoc build -m examples --target pbr --target-os ios
./examples/ios/pack.sh examples/ecobuild/pbr --resources examples/pbr/resources
xcrun simctl install booted var/Visu.app
xcrun simctl launch booted com.echolibs.visu
```

A connected iPhone uses the iPhoneOS SDK. That needs a development
certificate and a provisioning profile whose App ID is
`com.echolibs.visu` and whose device list includes the phone.

```bash
echoc build -m examples --target pbr --target-os ios --ios-device
./examples/ios/pack.sh examples/ecobuild/pbr --resources examples/pbr/resources \
    --identity 'Apple Development: Your Name (TEAMID)' \
    --profile path/to.mobileprovision
xcrun devicectl device install app --device DEVICE_ID var/Visu.app
xcrun devicectl device process launch --device DEVICE_ID com.echolibs.visu
```

Same recipe for `flyui`, `vg`, `clear`, `pipeline`, `shader`,
`quickstart`, `audio` — drop `--resources` when the example has none.
Audio needs the wavs:

```bash
echoc build -m examples --target audio --target-os ios
./examples/ios/pack.sh examples/ecobuild/audio --resources examples/audio/resources
```

`--target-os ios` on Darwin is a simulator cross-compile (triple
`arm64-apple-ios-simulator`). `echoc run --target-os ios` is refused.
