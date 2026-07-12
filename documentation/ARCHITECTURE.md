# Phase 1 architecture

## Boundaries

Kalpana Drive is an independent dashboard. It does not act as a CarPlay or Android Auto receiver and does not replace or modify the Ignis stereo. Audio routing remains under iPadOS and the existing Bluetooth system.

The repository uses these layers:

1. **Presentation** — SwiftUI dashboard and system-health UI.
2. **Domain** — state machines, models, provider contracts, and policies with no UI dependency.
3. **Data** — atomic local recovery snapshots; database-backed repositories are a later Phase 1 increment.
4. **Platform Services** — future MapKit, Core Location, MediaPlayer, AVFoundation, and speech adapters.
5. **Connectivity** — a common versioned envelope and platform-specific secure transports.
6. **Safety** — deterministic driving-state precedence and interaction restrictions.
7. **Automation** — reserved event/action boundary; automations must remain explainable and undoable.
8. **Diagnostics** — user-visible health with sensitive-value redaction.

Dependencies point inward: views consume protocols/models; platform adapters implement domain protocols. MapKit, a phone transport, an AI provider, or a media service can be replaced without changing the driving policy.

## State machines

`DrivingStateMachine` resolves signals in safety precedence order:

`EMERGENCY → THERMAL_LIMIT → LOW_POWER → PASSENGER_MODE → MOVING → OFFLINE → PHONE_DISCONNECTED → PARKED`

Movement begins at 1.4 m/s (about 5 km/h). Production location input should add accuracy checks and hysteresis before changing state. Passenger mode is explicit and always visible; it never silently activates.

Future explicit machines will cover connection, navigation, call, audio route, and voice-assistant lifecycle. Their states should be persisted only where recovery is meaningful and safe.

## Provider contracts

- Navigation: `NavigationProvider`, `RouteRepository`, `LocationProvider`, `DestinationSearchProvider`
- Media: `MediaSource`, `MediaController`, `AudioRouteManager`
- Phone: `PhoneConnection`
- Voice: `SpeechCommandRouter`

Phase 1 injects mock providers. Production providers must report unavailable capabilities honestly and use typed failures instead of fake success.

## Local data

Current models cover destinations, route recovery, media state, and phone connection state. `RecoveryStore` writes atomically with complete file protection. Sensitive future stores should use Keychain-held keys and an encrypted database; secrets must never enter `UserDefaults` or logs.

## Reliability

- The UI has immediate local fallback values and no indefinite loading state.
- Safety decisions are synchronous, deterministic, and unit tested.
- Recovery writes are atomic.
- Connectivity is not required for dashboard navigation, media control surface, emergency entry, or local commands.
- Expensive work will be suspended during thermal and low-power states.

