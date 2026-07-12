# Phase 1 status

## Implemented with live platform data

### iPad

- SwiftUI landscape dashboard.
- Live clock and date.
- MapKit map showing the iPad's real current location and heading.
- Core Location speed, course, heading, accuracy, freshness filtering, and stale-fix reporting.
- Network reachability using `NWPathMonitor`.
- iPad Apple Music metadata and playback commands using `MPMusicPlayerController`.
- Current audio-output inspection using `AVAudioSession`.
- Speech recognition and spoken responses using Speech and AVFoundation.
- Battery, charging, low-power, and thermal-state monitoring.
- Driving-state restrictions with sustained-speed hysteresis.
- One central safety-policy engine for dashboard, settings, media, contact browsing, number entry, calls, external media, device management, and emergency action classes.
- Event-driven service observation; one-second work is limited to the visible clock and periodic freshness reevaluation.
- MapKit place/address search, selectable results, route alternatives, polyline rendering, cancellation, and destination-based route recovery.
- Live system-health diagnostics.
- Atomic local recovery and route storage.

### iPhone companion

- SwiftUI companion source and XcodeGen application definition.
- Nearby iPad discovery with Multipeer Connectivity.
- Required session encryption and explicit approval on the iPad.
- Versioned typed messages, increasing sequence numbers, and replay/out-of-order rejection.
- Permission-driven Contacts loading and contact snapshot relay.
- iPhone Apple Music metadata relay and real play/pause/previous/next command handling.
- Optional foreground location sharing.
- Upcoming calendar-event location relay.
- Battery, charging, and network health relay.

### iPad/iPhone integration

- Connection status and approval UI.
- iPhone contacts shown and searchable on the iPad while parked.
- One-tap outgoing-call requests through the Apple system call interface.
- Separate controls for Apple Music playing on the iPad and Apple Music playing on the connected iPhone.
- Voice media commands prefer the connected iPhone when available.
- Manual number entry, contact browsing, device approval, and external media browsing are restricted by the central driving policy.

## Explicit platform limitations

- Native incoming iPhone cellular calls cannot be answered, rejected, intercepted, or reliably inspected by Kalpana Drive through public iOS APIs. They remain in Apple's Phone/Continuity interface.
- Outgoing calls require a valid iPad system calling route, such as Calls from iPhone/Continuity or another supported calling configuration.
- The iPhone media bridge controls the Apple Music system player only. Arbitrary Spotify, YouTube Music, and other third-party media sessions are not exposed to this app.
- Android companion connections are not implemented.
- Ignis vehicle telemetry is unavailable without a real tested read-only OBD-II integration.
- Genuine Apple CarPlay and Android Auto receiver modes are outside scope.

Unavailable capabilities must remain visibly unavailable. They must not be replaced with fixed values, synthetic events, fake success messages, static connection states presented as real, or interaction simulations.

## Security status

Implemented:

- Encrypted Multipeer sessions.
- Explicit per-connection approval on the iPad.
- Protocol version validation.
- Monotonic sequence validation and replay rejection.

Still required before permanent trust:

- Device-generated signing keys in Keychain.
- Signed mutual-authentication handshake.
- Trusted-device persistence based on cryptographic identity rather than display name.
- Key revocation and re-pairing flow.
- Payload size and rate limits.

## Validation status

- Core deterministic checks and iPad XCTest coverage exist.
- GitHub Actions generates and attempts to compile both Apple targets on macOS.
- The new iPhone companion and iPad bridge have not yet been verified together on physical devices.

Physical testing still required:

- Generate and sign both Xcode projects.
- Install the iPhone companion on a physical iPhone.
- Verify nearby discovery, approval, disconnect, and reconnect behavior.
- Verify contact permission and contact relay.
- Verify iPhone Apple Music metadata and commands.
- Verify outgoing calling through the actual Continuity configuration.
- Verify GPS speed during real road use.
- Verify Bluetooth audio routing with the Ignis stereo.
- Verify microphone recognition in cabin noise.
- Verify heat, direct sunlight, charging, low-power, and driving-lock behavior.

## Next production work

- Fix any Apple-build CI failures and commit regenerated Xcode projects.
- Add cryptographic device identity and revocation.
- Add saved Home, College, Work, favourites, and recent-place repositories.
- Add live route progress, step advancement, deviation detection, and recalculation.
- Add parking, trips, emergency mode, reminders, privacy controls, and UI tests.
- Build the Android companion only if Android phone integration is still required.
