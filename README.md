# Kalpana Drive

Kalpana Drive is an independent, driving-focused iPad dashboard for a Maruti Suzuki Ignis. It uses public Apple platform APIs and does **not** implement or emulate Apple CarPlay or Android Auto receiver protocols.

The repository follows one hard rule: **no demo data, mock services, simulated movement, fabricated connection states, or placeholder controls are allowed in the runnable application.** A capability either uses a real platform service or reports that it is unavailable.

## Implemented iPad capabilities

- Live MapKit map with the iPad's current location and heading.
- Real Core Location speed, permission state, and GPS accuracy.
- Real network reachability through `NWPathMonitor`.
- Real Apple Music metadata and transport controls through `MPMusicPlayerController`, plus an honest YouTube Music launch handoff (iPadOS does not expose third-party playback control).
- Real current audio-output inspection through `AVAudioSession`.
- Real battery, charging, low-power, and thermal state reporting.
- Real speech recognition and text-to-speech through Speech and AVFoundation.
- Driving-state restrictions calculated from live speed, power, thermal, network, and phone state.
- MapKit destination search, alternatives, route polylines, cancellation, and destination-based route recovery.
- Atomic local recovery storage and deterministic domain checks.

## Truthful unavailable states

Phone calls, phone notifications, and message relay remain unavailable until authenticated companion pairing is complete. The iPhone companion foundation provides real live health, destination search, and encrypted nearby discovery, but private-data sync remains disabled until device-identity approval and revocation are implemented.

## Repository layout

- `ipad-app/` — Swift iPad application, committed Xcode project, reproducible XcodeGen definition, and testable core
- `iphone-companion/` — installable SwiftUI iPhone companion foundation
- `shared-protocol/` — versioned device-message contract
- `documentation/` — architecture, safety, platform limitations, and implementation status
- `tests/` — validation plans and protocol fixtures
- `scripts/` — repeatable checks

## Required permissions

The iPad application Info.plist contains:

- `NSLocationWhenInUseUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`

Without these keys, iPadOS will correctly refuse the associated live capability.

## Build the iPad project

Requirements:

- Full Xcode installation with the iPadOS 17 SDK or newer
Open the committed `ipad-app/KalpanaDrive.xcodeproj`. XcodeGen is optional and is used only to regenerate the project after changing `project.yml`.

Select the `KalpanaDriveApp` scheme, configure your Apple development team, choose a physical iPad, and Run.

For a signing-free simulator compile check:

```bash
./scripts/build.sh
```

For dependency-free core checks:

```bash
./scripts/test.sh
```

GPS speed, Bluetooth audio routing, microphone input, battery state, and thermal behavior must be validated on physical hardware; simulator-only results are not accepted as production validation.
