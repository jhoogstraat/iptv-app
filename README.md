# iptv

Native SwiftUI IPTV client targeting Apple platforms.

## Status

This repository uses a pinned VLCKit 4 fat xcframework artifact. A fresh clone needs one setup step to download the exact locked version into `Vendor/VLCKit/VLCKit.xcframework`.

## Project Layout

- `iptv/`: app source
- `iptvTests/`: unit tests
- `iptvUITests/`: UI tests
- `docs/`: feature specs and notes

## Requirements

- Xcode 26+
- Network access to download the pinned VLCKit artifact

## Local VLCKit Setup

Run:

```sh
./scripts/fetch-vlckit
```

The pinned artifact URL and SHA-256 checksum live in [ThirdParty/vlckit.lock](ThirdParty/vlckit.lock).

## Build

```sh
./scripts/fetch-vlckit
xcodebuild -project iptv.xcodeproj -scheme iptv -configuration Debug build
```

## Test

```sh
./scripts/fetch-vlckit
xcodebuild -project iptv.xcodeproj -scheme iptv -destination 'platform=macOS' test
```

## Notes

- Provider credentials are stored at runtime in the keychain and are not committed to this repository.
- User-specific Xcode state should remain ignored.
