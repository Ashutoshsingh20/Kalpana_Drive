# Cross-platform test plan

Phase 1 executable tests live in `ipad-app/Tests`. Later phases must add fixtures and integration suites here for:

- malformed, stale, replayed, oversized, and unsupported protocol messages;
- TLS identity mismatch, revocation, reconnect backoff, stale heartbeat, and queue bounds;
- duplicate and sensitive-notification suppression;
- phone disconnection and dual-phone source switching;
- offline navigation recovery and provider timeouts;
- thermal, low-power, low-storage, slow-charge, and memory-pressure simulations;
- iPad landscape UI, Dynamic Type, VoiceOver, and moving-state interaction locks;
- safe database migrations and rollback fixtures.

No road testing is required for automated coverage: GPS, route, media, call, notification, weather, phone, and future OBD inputs must all have deterministic fakes.

