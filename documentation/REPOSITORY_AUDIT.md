# Repository audit

Audit baseline: PR #1, branch `agent/remove-simulated-services`, commit `a3c1170`.

## Existing architecture

- `KalpanaDriveCore` contains shared domain models, provider contracts, the driving-state resolver, design tokens, and an atomic JSON recovery store.
- `KalpanaDriveApp` is a SwiftUI iPad target generated from `project.yml` and backed by Core Location, MapKit, MediaPlayer, AVFoundation, Network, Speech, UIKit battery state, and ProcessInfo thermal state.
- A dependency-free Swift command target checks a small subset of core behavior.
- `shared-protocol` contains only a generic JSON envelope schema and prose security requirements.

## Verified working functions

- Core check target builds and passes seven baseline assertions.
- The generated Xcode project reaches the iOS app target with real Apple frameworks.
- Live MapKit user-location presentation, Core Location permission flow, iPad battery/thermal reporting, NWPathMonitor connectivity, MediaPlayer state/control, AVAudioSession route inspection, and push-to-talk speech adapters are present.
- Unavailable phone state is represented truthfully rather than fabricated.

## Build blockers found

- The PR does not compile under its declared Swift 6 strict-concurrency settings with Xcode 27: the main-actor `LiveLocationService` conformance crosses the nonisolated `CLLocationManagerDelegate` boundary. Fixed by making the imported Objective-C delegate conformance explicitly preconcurrency-safe while keeping state mutation on the main actor.
- The repository commits `project.yml` but not the generated `.xcodeproj`, contrary to the plan and README expectations. A normal user still needs XcodeGen.
- There are no Xcode unit-test or UI-test targets.

## Broken or incomplete production functions

- Driving state originally switched from one speed sample with no hysteresis and had no `LOCATION_UNAVAILABLE` state.
- A stale location remained usable indefinitely; location timestamp, course, heading, stale-fix detection, and reduced-accuracy status were absent.
- Dashboard state polls all services once per second instead of observing event-driven updates. The clock is the only value that needs one-second refresh.
- MapKit route calculation exists but no production UI can search/select a destination, show route geometry, update route progress, recalculate, persist, or restore it.
- Media does not observe playback/route/interruption notifications, expose artwork/album/route name, or report command failures.
- Speech only dispatches a few commands inside the dashboard view model. It has no typed intent/action/safety pipeline, live transcript UI, multilingual recognizer selection, confirmation, or reliable audio-session restoration.
- `PhoneCompanionService` is an unavailable-state shell. No Android or iPhone application exists.
- No parking, trip, emergency, saved-place, reminder, database, migration, encrypted-storage, trusted-device, automation, dual-phone, or notification implementation exists.
- Diagnostics are a partial live status list with no retry, Settings deep link, redacted export, storage/database state, heartbeat, route/trip state, or cache/reset actions.

## Removed production mocks

PR #1 removed the mock providers, delayed voice simulation, fixed Delhi coordinate, and simulated parked/moving control. No remaining production source matches mock, simulated, fake, or placeholder markers.

## Platform limitations

- iPadOS cannot read arbitrary iPhone notifications or intercept cellular telephony. iPhone integration must remain destination/location/calendar/preference handoff plus Continuity setup guidance.
- Third-party media control is limited to public system or partner APIs. The app must not claim arbitrary Spotify or YouTube Music control.
- AVAudioSession reports exposed routes; it cannot guarantee or force Ignis stereo reconnection.
- MapKit is not a complete offline turn-by-turn engine.
- Android call control depends on documented roles and permissions; notification replies require a live RemoteInput action.

## Security findings

- The current schema has no sequence field despite replay requirements, no typed payload schemas, and no executable validator.
- There is no identity-key generation, Keychain/Keystore storage, pairing ceremony, authenticated transport, replay cache, sequence window, revocation, capability negotiation, or rate limiting.
- Recovery JSON uses file protection but is not an encrypted database and should not hold future sensitive records without application-level encryption.

## Unsafe-driving findings

- There is no central action policy. Only the Settings button consults `restrictsInteraction`; Map, Music, Phone, bottom navigation, and voice actions bypass a shared policy.
- `PASSENGER_MODE` exists in the enum but has no explicit, visible, user-controlled production workflow.
- Emergency actions do not exist.
- Moving-mode keyboard, scrolling, route editing, message history, and complex-screen restrictions are not implemented or tested.

## Exact repair order

1. Keep the project compiling under Swift 6, commit a directly openable Xcode project, and add real Xcode test targets.
2. Complete filtered live location and state hysteresis, then replace broad polling with observation.
3. Add a central safety policy and gate every action.
4. Implement saved places, MapKit search/navigation/progress/recovery, real media/audio observation, and typed voice actions.
5. Add persistence-backed parking, trips, emergency, diagnostics, privacy, thermal, and offline behavior.
6. Replace the generic protocol with typed, authenticated, replay-protected Swift/Kotlin implementations and shared fixtures.
7. Build and test the Android companion, then the public-API-limited iPhone companion and dual-phone manager.
8. Add CI, complete install scripts, device tests, feature and permission matrices, release checklist, and known issues.
