# Security and privacy baseline

- Local-first operation; cloud services are optional and visible.
- No background microphone recording or silent message sending.
- No OTP, banking, authentication-code, redacted phone content, or precise location in notifications or logs.
- Pairing requires an in-person PIN or QR ceremony and mutual identity verification.
- Trusted devices are revocable. Revocation closes active sessions.
- Sensitive local data requires file protection plus application-level encryption with Keychain-held keys before production storage.
- Incoming protocol data is untrusted: validate size, version, timestamp, nonce, authentication, type, and payload before dispatch.
- Message/reply/call actions require safety-policy evaluation and explicit confirmation where sensitive.
- Diagnostics expose capability state and coarse failure reasons, never credentials or private content.

Threat modelling and penetration testing are required before any companion release.

