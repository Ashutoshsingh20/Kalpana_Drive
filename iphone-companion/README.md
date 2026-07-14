# Kalpana Drive Phone

Kalpana Drive Phone is the iPhone companion for the iPad dashboard. It uses public Apple APIs and shares data only after the user grants each permission and establishes a nearby encrypted Multipeer Connectivity session.

## Implemented

- Nearby iPad discovery through Multipeer Connectivity.
- User-initiated connection to the iPad.
- Required transport encryption through `MCSession`.
- Contacts permission, local contact loading, and contact snapshot relay.
- Apple Music permission, current Apple Music metadata, and play/pause/previous/next command execution.
- Optional foreground location sharing.
- Upcoming calendar-event location relay.
- Battery, charging, and network health relay.
- Typed, versioned JSON messages with monotonically increasing sequence numbers.
- Replay and out-of-order message rejection.
- Explicit user-facing explanation of Apple platform limitations.

## Important limitation

The app cannot answer, reject, intercept, or inspect native iPhone cellular calls. Apple does not expose those controls to third-party apps. Kalpana Drive can share approved contacts and request an outgoing call through the iPad system Phone/Continuity interface, but incoming cellular calls remain controlled by Apple's interface.

The Apple Music bridge controls the iPhone `MPMusicPlayerController.systemMusicPlayer`. It does not provide universal access to Spotify, YouTube Music, or arbitrary third-party media sessions.

## Security status

Multipeer transport encryption is required, sequence validation rejects replayed messages, and the iPad asks the user to approve each incoming connection. Persistent cryptographic device identity, key revocation, and a signed reconnection handshake are not complete yet. Until those are implemented, do not treat a previously seen peer name as proof of identity.

## Generate and build

Requirements:

- Full Xcode installation with the iOS 17 SDK or newer
- XcodeGen

```bash
cd iphone-companion
xcodegen generate
open KalpanaDrivePhone.xcodeproj
```

Select your Apple development team, choose a physical iPhone, and Run. Nearby discovery and Apple Music behavior must be tested on physical devices.

A signing-free simulator compile check can be run from the repository root:

```bash
./scripts/build-iphone.sh
```

The iPhone companion currently compiles successfully in GitHub Actions with Xcode 16.4.
