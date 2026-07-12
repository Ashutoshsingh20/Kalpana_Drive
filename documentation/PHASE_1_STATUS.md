# Phase 1 status

## Working now

- SwiftUI application shell with a landscape dashboard.
- Live clock/date.
- Clearly labelled placeholder map and simulated GPS speed.
- Deterministic parked/moving simulation through System Health.
- Navigation, media, and phone cards.
- Simulated local media play/pause state.
- Day/night/high-sunlight appearance selection.
- Home, Map, Music, Phone, and Settings controls.
- Push-to-talk interaction simulation using a local intent router.
- Provider abstractions for navigation, routes, location, search, media, audio route, phone connection, and voice commands.
- Atomic recovery store and executable domain checks.
- Versioned shared-protocol envelope schema and security contract.

## Platform limitations

- This environment has Swift installed but its active developer directory is an incomplete Command Line Tools build, not full Xcode. The dependency-free domain check target can be verified here; XCTest, an iPadOS SDK build, and simulator run cannot be honestly claimed until opened with full Xcode.
- GPS, MapKit routing, Bluetooth route inspection, speech recognition, text-to-speech, battery/thermal monitoring, and Apple Music are provider contracts or UI placeholders, not live integrations yet.
- iPadOS does not provide unrestricted phone notification or telephony interception. iPhone behavior will coexist with supported Continuity features.
- The Ignis stereo exposes only capabilities supported by its Bluetooth profile and iPadOS public APIs; Kalpana Drive cannot guarantee third-party app control or force audio reconnection.
- Offline turn-by-turn routing is limited by the selected navigation provider. Phase 1 persists route state but does not claim a full offline map engine.

## Incomplete Phase 1 work

- Live Core Location and motion adapter with accuracy filtering/hysteresis.
- MapKit search, route calculation, alternatives, and restored route rendering.
- Saved-place repository and full settings persistence.
- Real MediaPlayer/AVFoundation adapters and audio ducking.
- Speech framework adapter, interruptible synthesis, and confirmation UI.
- Emergency screen and offline checklists.
- Battery, charging, network, storage, and thermal health adapters.
- Real crash launch detection and recovery orchestration around `RecoveryStore`.
- UI tests on iPad sizes, accessibility audit, and physical-device heat/power testing.

These are not represented as complete in the app.
