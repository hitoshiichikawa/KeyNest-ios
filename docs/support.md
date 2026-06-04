---
title: Support
---

# Support

Last updated: 2026-06-04

Thank you for using KeyNest. If you need help, have a question, or want to
report a problem, please use one of the channels below.

## Contact

- Email: hitoshi.ichikawa@gmail.com
- GitHub Issues: [https://github.com/hitoshiichikawa/KeyNest-ios/issues](https://github.com/hitoshiichikawa/KeyNest-ios/issues)

Please include your device model, iOS version, and a description of the
steps to reproduce the problem when reporting an issue.

## Known Issues

TBD.

A list of currently known issues will be published here as needed.

## Frequently Asked Questions (FAQ)

### Passkeys

**I lost my iPhone or iPad (or did a factory reset). Can I recover my passkeys?**

No. Passkeys are stored only on the device, and KeyNest provides no export
or backup function for them. If the device is lost, wiped, or reset, the
passkeys it held cannot be recovered. You will need to register a new
passkey on each relying party (the website or app) using that service's own
account-recovery or re-registration flow.

**Can I move my passkeys to another device?**

Not at this time. KeyNest does not support cross-device sync or transfer of
passkeys, because the Credential Exchange Protocol is not yet implemented.
Each device keeps its own passkeys, and you register passkeys separately
on each device you want to use.

**How do I stop KeyNest from acting as my passkey provider?**

Passkey providers are managed by iOS, not inside KeyNest. Open the system
**Settings** app and go to **Passwords ▸ AutoFill Passwords & Passkeys**
(under General on some iOS versions). From there you can disable KeyNest
or change the default provider. KeyNest also offers a shortcut to this
system screen from its Onboarding and Settings screens.

### AutoFill

**KeyNest is not appearing in the AutoFill picker.**

iOS only lists providers that have been enabled in **Settings ▸ Passwords ▸
AutoFill Passwords & Passkeys**. After installing or updating KeyNest,
re-open that panel and confirm KeyNest is toggled on. Force-quitting Safari
and re-opening the login form sometimes refreshes the picker.

**The AutoFill extension takes a moment to open the first time.**

The first time the system loads any AutoFill extension (KeyNest or another),
iOS has to spin up a fresh process and load the relevant frameworks. Once
the process is warm the extension opens near-instantly. This applies to
every third-party AutoFill provider, not just KeyNest.
