# Repository audit

Current audit scope: PR #1, branch `agent/remove-simulated-services`.

## Current architecture

- `KalpanaDriveCore` contains driving-state logic, the central safety policy, shared domain models, route persistence, design tokens, and recovery storage.
- `KalpanaDriveApp` is a SwiftUI iPad application backed by Core Location, MapKit, MediaPlayer, AVFoundation, Network, Speech, UIKit device state, and Multipeer Connectivity.
- `KalpanaDrivePhone` is a SwiftUI iPhone companion source target backed by Contacts, MediaPlayer, EventKit, Core Location, Network, and Multipeer Connectivity.
- The iPad advertises a nearby companion service. The iPhone browses and requests a connection; the iPad must explicitly approve it.
- Both Apple targets use typed versioned JSON envelopes, increasing sequence numbers, and replay/out-of-order rejection.
- GitHub Actions generates both Xcode projects and compiles both simulator targets on macOS.

## Implemented live functions

- Filtered live GPS location, speed, heading, course, accuracy, and stale-fix detection.
- Sustained-speed movement hysteresis.
- MapKit place search, route alternatives, route polylines, cancellation, and destination-based recovery.
- iPad Apple Music controls and audio-route inspection.
- Push-to-talk speech recognition and synthesis.
- Battery, charging, network, low-power, and thermal status.
- Central driving policy for typing, contact browsing, manual number entry, one-tap calls, settings, media, external content, device approval, and emergency classes.
- iPhone contact permission, contact loading, and contact snapshot relay.
- iPhone Apple Music metadata and play/pause/previous/next command relay.
- Optional foreground iPhone location sharing.
- Calendar-event destination and device-health relay.
- iPad contact search and outgoing-call request through the system calling interface.
- Explicit encrypted-session approval and protocol sequence validation.

## Removed production simulations

- Fixed Delhi coordinates.
- Manual moving/parked simulation.
- Fabricated media metadata.
- Mock phone connection state.
- Delayed voice-response simulation.
- Mock location, navigation, media, phone, and audio providers.

## Current build state

- Dependency-free core checks pass in GitHub Actions.
- XcodeGen successfully generates both Apple projects.
- The iPad simulator application target compiles with Xcode 16.4.
- The iPhone simulator companion target compiles with Xcode 16.4.
- Compiler logs are retained as workflow artifacts.
- The committed iPad `.xcodeproj` predates some companion work; build scripts regenerate it when necessary. Fresh generated projects should be committed before release.

## Remaining functional gaps

- Navigation does not yet advance route steps, calculate live remaining distance, detect deviations, reroute, or announce turns.
- Saved Home, College, Work, favourites, and recent-place repositories are incomplete.
- Voice intent handling is still embedded in the dashboard view model and covers only a small command set.
- Media does not yet expose artwork or robustly restore every audio session after speech/interruption.
- Parking, trip recording, emergency mode, reminders, maintenance records, encrypted application storage, and privacy retention controls do not exist.
- Diagnostics lack permission retry, settings deep links, redacted export, storage/database status, and reset actions.
- Android companion and notification relay do not exist.
- UI-test coverage is missing.

## Apple platform limits

- Native iPhone cellular calls cannot be answered, rejected, intercepted, or reliably inspected by the companion through public iOS APIs.
- Outgoing calls rely on the Apple system calling interface and a working Continuity/cellular calling route.
- The iPhone media bridge controls Apple Music only; it cannot universally control Spotify, YouTube Music, or arbitrary third-party sessions.
- iPadOS cannot read arbitrary iPhone notifications.
- AVAudioSession cannot force the Ignis stereo to reconnect.
- MapKit is not a complete offline turn-by-turn engine.

## Security findings

Implemented:

- Required Multipeer session encryption.
- Explicit approval of each incoming connection.
- Protocol-version checks.
- Monotonic sequence validation and replay rejection.

Still missing:

- Keychain-backed signing identities.
- Signed mutual authentication.
- Cryptographically trusted-device persistence.
- Key revocation and re-pairing.
- Payload size limits, rate limits, and capability negotiation enforcement.
- Encrypted database storage for future sensitive history.

A peer display name is not proof of identity. The current connection must not be described as permanently trusted.

## Unsafe-driving findings still open

- Passenger mode has no complete visible activation and expiration workflow.
- Emergency actions are classified but no emergency screen exists.
- One-tap calls are permitted while moving, but favourites and caller-priority design still need validation.
- Voice call requests need physical testing to ensure the system call interface does not cause unsafe visual transitions.
- UI tests must verify keyboard and long-list suppression while moving.

## Next repair order

1. Commit freshly generated Xcode projects and add iPhone unit tests.
2. Add Keychain identities, signed pairing, revocation, payload limits, and rate limits.
3. Add saved places and live navigation progress/rerouting.
4. Add parking, trips, emergency mode, reminders, privacy, and diagnostics.
5. Add physical-device iPad/iPhone testing in the Ignis.
6. Build an Android companion only if broader notification and media-session access remains required.
