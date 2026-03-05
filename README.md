# iptv

Native SwiftUI IPTV client targeting Apple platforms.

## Status

This repository uses pinned VLCKit 4 binary artifacts. A fresh clone needs one setup step to download the exact locked versions into `Vendor/VLCKit/`.

## Project Layout

- `iptv/`: app source
- `iptvTests/`: unit tests
- `iptvUITests/`: UI tests
- `docs/`: feature specs and notes

## Requirements

- Xcode 26+
- Network access to download the pinned VLCKit artifacts

## Local VLCKit Setup

Run:

```sh
./scripts/fetch-vlckit
```

The pinned artifact URLs and SHA-256 checksums live in [ThirdParty/vlckit.lock](/Users/U765382/Developer/iptv/ThirdParty/vlckit.lock).

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
