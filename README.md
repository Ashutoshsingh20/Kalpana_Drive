# Kalpana Drive

Kalpana Drive is an independent driving-focused application for an iPad mounted in a Maruti Suzuki Ignis. The iPad can provide navigation, YouTube Music, Siri actions, GPS, audio-route status, battery and thermal monitoring without a connected phone. An iPhone companion remains an optional extension for contacts and supported Apple Music relay.

Kalpana Drive uses public Apple and Google web-platform capabilities. It does **not** implement or emulate Apple CarPlay or Android Auto receiver protocols.

The repository follows one hard rule: **no demo data, mock services, simulated movement, fabricated connection states, or placeholder success are allowed in production.** A capability either uses a real platform service or reports that it is unavailable.

## Independent iPad capabilities

- Live MapKit map with the iPad's current location and heading.
- Core Location speed, permission state, freshness filtering and GPS accuracy.
- MapKit destination search for places, landmarks, businesses and addresses.
- Nearby-first destination search with an automatic global retry when no nearby result exists.
- Destination searching while parked even before a valid GPS fix is available.
- Driving-route alternatives, route polylines, cancellation and destination-based route recovery.
- YouTube Music loaded directly inside Kalpana Drive using a persistent `WKWebView` on the iPad.
- Inline media playback routed through the iPad and its current Bluetooth or speaker output.
- Siri App Intents and App Shortcuts for opening the dashboard, map and YouTube Music, plus destination search.
- Siri remains a system overlay, so the Kalpana Drive dashboard stays underneath and returns to the requested screen or task.
- Network reachability through `NWPathMonitor`.
- Current audio-output inspection through `AVAudioSession`.
- Battery, charging, low-power and thermal-state reporting.
- Driving-state hysteresis and a central action-safety policy.
- Atomic local recovery storage and deterministic domain checks.

## Siri phrases

After installing and opening the application, use phrases such as:

- “Siri, open the dashboard in Kalpana Drive.”
- “Siri, open the map in Kalpana Drive.”
- “Siri, open YouTube Music in Kalpana Drive.”
- “Siri, search a destination in Kalpana Drive.”

For destination search, Siri asks which place to search for and opens the result flow in Kalpana Drive.

Apps cannot programmatically press the Siri button or embed the full Siri interface. Siri must be activated by voice or the iPad's top button.

## Optional iPhone companion

- Nearby iPad discovery and user-initiated connection.
- Contacts permission and approved contact snapshot relay.
- Apple Music permission, metadata relay and play/pause/previous/next command handling.
- Optional foreground location sharing.
- Upcoming calendar-event location relay.
- Battery, charging and network-health relay.
- Typed versioned messages with monotonically increasing sequence numbers.

The iPhone companion is not required for the iPad map, YouTube Music or Siri functions.

## Platform limits

- YouTube Music runs through Google's website inside WebKit. Google can change sign-in, playback or embedding behavior, so it must be verified on the physical iPad.
- Kalpana Drive cannot universally inspect or control arbitrary playback in other third-party applications.
- Native incoming iPhone cellular calls remain in Apple's Phone/Continuity interface.
- Siri is integrated using App Intents and App Shortcuts; a third-party app cannot replace or privately invoke the full Siri interface.

## Repository layout

- `ipad-app/` — Swift iPad application, XcodeGen definition, testable core, WebKit media surface and Siri App Intents
- `iphone-companion/` — optional SwiftUI iPhone companion source and XcodeGen definition
- `shared-protocol/` — protocol specification work
- `documentation/` — architecture, safety, limitations and status
- `tests/` — test plans and fixtures
- `scripts/` — project generation, builds and checks

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

Select your Apple development team and install the iPad application on a physical iPad. The companion can be installed later when phone integration is required.

## Build checks

```bash
./scripts/test.sh
./scripts/build.sh
./scripts/build-iphone.sh
```

GitHub Actions has generated and compiled both Apple simulator targets with Xcode 16.4 after the independent-iPad changes.

Physical-device verification is still required for YouTube Music sign-in and playback, Siri shortcut discovery, MapKit results in India, GPS speed, Bluetooth audio routing, heat and charging behavior.
