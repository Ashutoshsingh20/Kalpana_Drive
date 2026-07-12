# Kalpana Drive

Kalpana Drive is an independent, driving-focused iPad dashboard for a Maruti Suzuki Ignis. It uses public Apple platform APIs and does **not** implement or emulate Apple CarPlay or Android Auto receiver protocols.

The repository follows one hard rule: **no demo data, mock services, simulated movement, fabricated connection states, or placeholder controls are allowed in the runnable application.** A capability either uses a real platform service or reports that it is unavailable.

## Implemented iPad capabilities

- Live MapKit map with the iPad's current location and heading.
- Real Core Location speed, permission state, and GPS accuracy.
- Real network reachability through `NWPathMonitor`.
- Real Apple system-music metadata and transport controls through `MPMusicPlayerController`.
- Real current audio-output inspection through `AVAudioSession`.
- Real battery, charging, low-power, and thermal state reporting.
- Real speech recognition and text-to-speech through Speech and AVFoundation.
- Driving-state restrictions calculated from live speed, power, thermal, network, and phone state.
- MapKit driving-route service for real destinations.
- Atomic local recovery storage and deterministic domain checks.

## Truthful unavailable states

Phone calls, phone notifications, and cross-device messaging remain unavailable until real authenticated iPhone and Android companion applications are implemented. The iPad UI does not fabricate these features or display pretend phone data.

## Repository layout

- `ipad-app/` — Swift iPad application, XcodeGen project definition, and testable core
- `shared-protocol/` — versioned device-message contract for future real companions
- `documentation/` — architecture, safety, platform limitations, and implementation status
- `tests/` — validation plans and protocol fixtures
- `scripts/` — repeatable checks

## Required permissions

The iPad application Info.plist contains:

- `NSLocationWhenInUseUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`

Without these keys, iPadOS will correctly refuse the associated live capability.

## Generate and build the iPad project

Requirements:

- Full Xcode installation with the iPadOS 17 SDK or newer
- XcodeGen

```bash
cd ipad-app
xcodegen generate
open KalpanaDrive.xcodeproj
```

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
