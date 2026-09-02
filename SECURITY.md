# Security Policy

Mousetrapped is a small, unsandboxed macOS utility that can be granted the
Input Monitoring permission. That level of trust deserves scrutiny, so
security reports are taken seriously.

## What the app does with its access

- With Input Monitoring granted, it observes raw mouse deltas and a handful
  of key states (the hotkey chord modifiers plus one key) via IOHIDManager.
- Nothing is recorded, stored, or transmitted. Input never leaves the
  machine.
- The only network request is the update check: an unauthenticated GET to
  `https://api.github.com/repos/uncSoft/Mousetrapped/releases/latest` to
  compare the latest release tag against the running version. It sends no
  query parameters or personal data, runs at most once a day, and can be
  turned off in the menu (*Check Automatically*). Nothing is downloaded or
  installed; the app only points you at the release page or the brew
  command.
- Logs go to the local unified log only, and never contain key or movement
  data (per-stroke logging is opt-in, local, and records distances and
  directions, not content).
- The one privileged-feeling action it takes is sending SIGKILL to the
  UniversalControl agent, and only in response to your own rescue trigger.

Anything that contradicts the above in the shipped code is a bug worth
reporting, security or otherwise.

## Reporting a vulnerability

Please report vulnerabilities privately rather than opening a public issue:

- Preferred: [GitHub private vulnerability reporting](https://github.com/uncSoft/Mousetrapped/security/advisories/new)
- Or email: jt@devpadapp.com

Include what you found, steps to reproduce, and the app version (About
window) or commit hash. You can expect an acknowledgment within a few days.
Fixes ship as a new notarized release; credit is given unless you prefer
otherwise.

## Supported versions

Only the latest release receives security fixes. There is no backporting;
update to the newest version.

## Verifying builds

Release builds are signed with a Developer ID certificate
(`Developer ID Application: John Taverna (J7NK5LQP48)`) and notarized by
Apple. Verify a download with:

```bash
spctl -a -vv -t exec Mousetrapped.app
codesign -dv --verify Mousetrapped.app
```

If either check fails, the build did not come from this project's release
pipeline; delete it and download from
[Releases](https://github.com/uncSoft/Mousetrapped/releases/latest).
