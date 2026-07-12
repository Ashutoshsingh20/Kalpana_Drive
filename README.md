# Kalpana Drive

Kalpana Drive is an independent driving-focused system for an iPad mounted in a Maruti Suzuki Ignis, with an iPhone companion. It uses public Apple APIs and does **not** implement or emulate Apple CarPlay or Android Auto receiver protocols.

The repository follows one hard rule: **no demo data, mock services, simulated movement, fabricated connection states, or placeholder success are allowed in production.** A capability either uses a real platform service or reports that it is unavailable.

## Implemented iPad capabilities

- Live MapKit map with the iPad's current location and heading.
- Real Core Location speed, permission state, freshness filtering, and GPS accuracy.
- Real network reachability through `NWPathMonitor`.
- Real iPad Apple Music metadata and transport controls through `MPMusicPlayerController`.
- Real current audio-output inspection through `AVAudioSession`.
- Real battery, charging, low-power, and thermal state reporting.
- Real speech recognition and text-to-speech through Speech and AVFoundation.
- Driving-state hysteresis and a central action-safety policy.
- MapKit destination search, alternatives, route polylines, cancellation, and destination-based route recovery.
- Atomic local recovery storage and deterministic domain checks.
- Nearby iPhone advertising, explicit connection approval, required Multipeer transport encryption, sequence validation, and replay rejection.
- iPhone contact display, search, one-tap outgoing-call initiation through the Apple system interface, and remote iPhone Apple Music controls.

## Implemented iPhone companion

- Nearby iPad discovery and user-initiated connection.
- Contacts permission and approved contact snapshot relay.
- Apple Music permission, metadata relay, and play/pause/previous/next command handling.
- Optional foreground location sharing.
- Upcoming calendar-event location relay.
- Battery, charging, and network-health relay.
- Typed versioned messages with monotonically increasing sequence numbers.

## Apple platform limits

- Native incoming cellular calls remain in Apple's Phone/Continuity interface. Third-party apps cannot answer, reject, intercept, or reliably inspect those calls through public iOS APIs.
- Outgoing calls are requested through the iPad system `tel:` interface and require a working cellular or Calls from iPhone/Continuity configuration.
- The iPhone media bridge controls the iPhone Apple Music system player. It cannot universally inspect or control Spotify, YouTube Music, or arbitrary third-party media sessions.
- Multipeer transport encryption and per-connection approval are implemented. Persistent cryptographic device identity, signed reconnection, and device-key revocation are still required before the connection should be treated as permanently trusted.

## Repository layout

- `ipad-app/` — Swift iPad application, XcodeGen definition, testable core, and iPhone bridge
- `iphone-companion/` — SwiftUI iPhone companion source and XcodeGen definition
- `shared-protocol/` — protocol specification work
- `documentation/` — architecture, safety, limitations, and status
- `tests/` — test plans and fixtures
- `scripts/` — project generation, builds, and checks

## Generate both Xcode projects

Requirements:

- Full Xcode installation with iOS/iPadOS 17 SDK or newer
- XcodeGen

```bash
./scripts/generate-projects.sh
```

This generates:

- `ipad-app/KalpanaDrive.xcodeproj`
- `iphone-companion/KalpanaDrivePhone.xcodeproj`

Select your Apple development team in each project and install both apps on physical devices.

## Build checks

```bash
./scripts/test.sh
./scripts/build.sh
./scripts/build-iphone.sh
```

GitHub Actions has successfully generated and compiled both Apple simulator targets with Xcode 16.4.

GPS speed, Bluetooth audio routing, microphone recognition, iPhone discovery, contact relay, Apple Music commands, calling handoff, heat, and charging behavior still require physical-device verification.
