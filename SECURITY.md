# Security

Yolk inspects and can signal other processes belonging to your user. Changes around ownership checks, PID reuse, icon parsing, filesystem access and local-network requests deserve particular care.

Please use the repository's **Security → Report a vulnerability** feature when private vulnerability reporting is enabled. Do not publish exploit details or private process information in a public issue. If the private channel is unavailable, open a minimal issue asking the maintainer to enable it, without including the vulnerability details.

This is an early beta. The latest beta is the active maintenance target; there is no promised backport schedule. The app requests no administrator privileges and does not use App Sandbox because its process-inspection function needs access outside it. HTTPS certificate validation is not bypassed.
