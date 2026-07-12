# Kalpana Drive

Kalpana Drive is an independent, driving-focused iPad dashboard for a Maruti Suzuki Ignis. It uses public platform APIs and does **not** implement or emulate Apple CarPlay or Android Auto receiver protocols.

This repository currently contains the Phase 1 iPad foundation: a compilable SwiftUI dashboard, safety state machine, provider abstractions, mock services, local recovery state, diagnostics, and unit tests. The phone companion directories are intentionally Phase 2/3 placeholders.

## Repository layout

- `ipad-app/` — Swift Package containing the iPad app and testable core
- `iphone-companion/` — Phase 3 scope placeholder
- `android-companion/` — Phase 2 scope placeholder
- `shared-protocol/` — versioned cross-device protocol contract
- `documentation/` — architecture, safety, limitations, and status
- `tests/` — cross-platform test plans and fixtures
- `scripts/` — repeatable build and test commands

## Build and test

```bash
./scripts/test.sh
./scripts/build.sh
```

Open `ipad-app/Package.swift` in a full Xcode installation, select the `KalpanaDriveApp` scheme and an iPad simulator/device, then Run. Command-line validation requires Swift 6.0 or newer. A full iPad build requires Xcode with the iPadOS SDK.

## Phase 1 status

See [`documentation/PHASE_1_STATUS.md`](documentation/PHASE_1_STATUS.md). All simulated values are labelled in the UI; no phone, vehicle, Bluetooth-control, or turn-by-turn capability is fabricated.

