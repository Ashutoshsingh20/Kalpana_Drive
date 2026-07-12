# Phase 1 status

## Implemented with live platform data

- SwiftUI landscape dashboard for iPad.
- Live clock and date.
- MapKit map showing the iPad's real current location and heading.
- Core Location speed, course, heading, accuracy, freshness filtering, and stale-fix reporting.
- Network reachability using `NWPathMonitor`.
- Current system-music metadata and playback commands using `MPMusicPlayerController`.
- Current audio-output inspection using `AVAudioSession`.
- Speech recognition and spoken responses using Speech and AVFoundation.
- Battery, charging, low-power, and thermal-state monitoring.
- Driving-state restrictions derived from live system state with sustained-speed hysteresis.
- One central safety-policy engine gates dashboard, settings, voice, media, typing, browsing, device-management, and emergency action classes.
- Event-driven service observation; the one-second task updates only the clock and stale-fix safety is reevaluated every five seconds.
- MapKit route calculation service for real destinations.
- Live system-health diagnostics.
- Atomic local recovery store, 21 deterministic domain checks, and an XCTest target running on iPad Simulator.
- Versioned shared-protocol envelope and security contract.

## Explicitly unavailable

- iPhone and Android companion connections are not implemented.
- Calls, phone notifications, message replies, and phone media relay are not displayed or represented as functional.
- Ignis vehicle telemetry is unavailable without a real, tested OBD-II integration.
- Genuine Apple CarPlay and Android Auto receiver modes are outside product scope.

Unavailable capabilities must remain visibly unavailable. They must not be replaced with fixed values, synthetic events, fake success messages, static connection states presented as real, or interaction simulations.

## Physical-device validation

- Signed Debug build, installation, launch, and process presence verified on the connected iPad (10th generation), bundle `com.ashutoshsingh.kalpanadrive`, version `1.0 (1)`.

Still required:

- Verify GPS accuracy and speed behavior during real road use.
- Verify Bluetooth A2DP/HFP/car-audio route detection with the Ignis stereo.
- Verify microphone recognition in cabin noise.
- Verify Apple Music transport control behavior.
- Verify heat, direct sunlight, charging, and low-power behavior.
- Verify driving-lock behavior across low-speed traffic and GPS drift.

## Next production work

- Add a saved-place repository and real MapKit destination-search UI.
- Render active MapKit route polylines and step progress.
- Add route recovery across process termination.
- Build authenticated companion apps before enabling phone features.
- Add emergency UI backed by real system calling and location-sharing capabilities.
- Add UI-test coverage for landscape layout and moving-state restrictions.
