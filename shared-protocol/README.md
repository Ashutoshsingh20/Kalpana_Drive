# Kalpana Drive Shared Protocol

The cross-device wire protocol is reserved for Phase 2. Its contract is defined now so that the iPad, Android, and iPhone implementations converge on one versioned format.

Every envelope includes `version`, `id`, `type`, `deviceId`, `timestamp`, `nonce`, and a typed `payload`. Implementations must reject unknown mandatory fields, stale timestamps, repeated IDs/nonces, invalid signatures, unsupported versions, oversized payloads, and messages received before authentication.

Transport requirements:

- iPhone/iPad: authenticated Multipeer Connectivity encryption or TLS over Network.framework.
- Android/iPad: TLS 1.3 WebSocket on the local network.
- Pairing: user-visible six-digit PIN or QR bootstrap, followed by device identity pinning.
- Identity secrets: iOS Keychain and Android Keystore.
- Session: ephemeral key agreement, transcript-bound authentication, rotation on reconnect and periodically.
- Logging: metadata only; notification bodies, tokens, coordinates, contacts, and message text are redacted.
- Replay window: timestamp tolerance plus a bounded cache of message IDs and nonces.
- Revocation: deletes the pinned identity and closes active sessions immediately.
- Rate limits: per-message-type quotas and bounded queues.

See `schema-v1.json` for the machine-readable envelope and message type registry. Payload schemas will be tightened alongside each Phase 2 capability; an unimplemented payload type must be rejected, not silently accepted.

