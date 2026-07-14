# Phase 1 status

## Independent iPad application

Implemented with live platform data:

- SwiftUI landscape dashboard for iPad.
- Live clock, date, battery, charging, network, thermal and audio-route state.
- MapKit map showing the iPad's real current location and heading.
- Core Location speed, course, heading, accuracy, freshness filtering and stale-fix reporting.
- Destination search for places, landmarks, businesses and addresses.
- Nearby-first search with automatic global retry when the place is outside the current region.
- Destination search remains usable while parked when GPS permission or a fresh fix is unavailable.
- Route alternatives, route polylines, cancellation and destination-based route recovery.
- YouTube Music inside the application through a persistent WebKit browser surface.
- Siri App Intents and App Shortcuts for dashboard, map, YouTube Music and destination search actions.
- Driving-state hysteresis and a central safety-policy engine.
- Live system-health diagnostics.
- Atomic local recovery and deterministic domain checks.

The iPhone companion is optional. The iPad does not require it for map search, navigation planning, YouTube Music, Siri tasks, GPS or diagnostics.

## Siri behavior

Siri remains Apple's system assistant. Kalpana Drive exposes supported tasks through App Intents and App Shortcuts. Siri is activated using voice or the iPad's top button and appears as a system overlay; the app cannot programmatically display or embed Siri itself.

Supported initial shortcuts:

- Open dashboard.
- Open map.
- Open YouTube Music.
- Search a destination, with Siri prompting for the place.

## YouTube Music behavior

The Music section opens `music.youtube.com` inside a persistent `WKWebView`, allowing search and playback without leaving Kalpana Drive. Playback originates on the iPad and follows the iPad's active audio route.

This is a web integration rather than a private YouTube Music SDK. Physical-device validation is required for Google sign-in, account persistence, background audio behavior and Bluetooth routing.

## Optional iPhone companion

Implemented foundation:

- Encrypted nearby Multipeer session.
- Explicit iPad approval.
- Contacts relay.
- Supported Apple Music state and commands.
- Optional foreground location and calendar destinations.
- Device-health relay.
- Protocol version and replay checks.

Still incomplete:

- Permanent signed device identity and revocation.
- Native incoming cellular-call control, which is not exposed by public iOS APIs.
- Notification and message relay.

## Validation completed

GitHub Actions with Xcode 16.4 successfully:

- Generated both Xcode projects.
- Passed the core checks.
- Compiled the independent iPad application with WebKit and Siri App Intents.
- Compiled the optional iPhone companion.

## Physical-device validation still required

- YouTube Music sign-in, search, playback and session persistence.
- Siri shortcut discovery and spoken destination prompts.
- MapKit search quality for Indian places and addresses.
- Route calculation from the actual iPad position.
- GPS speed and movement hysteresis during road use.
- Ignis Bluetooth audio routing.
- Direct sunlight, charging and thermal behavior.

## Next production work

- Test and refine the new independent-iPad experience on the physical iPad.
- Add active route progress, current-step advancement, deviation detection and rerouting.
- Add saved Home, College, Work and favourite destinations.
- Add parking and trip persistence.
- Add emergency controls.
- Remove the legacy custom speech service after Siri device validation confirms the replacement workflow.
