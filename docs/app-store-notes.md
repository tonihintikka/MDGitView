# App Store migration notes (future)

This project is currently configured for local/developer distribution workflow, but the architecture is App Store migration-friendly.

## Areas to validate before Mac App Store submission

- Mermaid and MathJax are vendored under `Resources/Assets/`; maintain with `./scripts/update_third_party.sh` (see `ThirdParty/versions.json`).
- Confirm all extension Info.plist keys match current App Review expectations.
- Audit privacy declarations and add `PrivacyInfo.xcprivacy` manifest entries for all included SDKs/libraries as needed.
- Validate sandbox file access in Quick Look extensions under App Review runtime constraints.
- Run full signing/notarization checks on release archive and test Gatekeeper install path.
