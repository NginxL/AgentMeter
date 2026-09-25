# Development

[简体中文](DEVELOPMENT.zh-CN.md) · [README](../README.md) · [Privacy](PRIVACY.md)

## Local build

Use macOS 14 or later with Apple Command Line Tools providing Swift 5.9+ and a macOS 14+ SDK. The project uses Swift Package Manager and system frameworks only. An Xcode project and a paid Apple Developer account are not required for local builds.

```bash
bash scripts/test.sh
bash scripts/build.sh
open dist/AgentMeter.app
```

`scripts/test.sh` runs `swift run MeterChecks` for core checks, `swift run MeterProviderChecks` for Codex/Claude adapter checks, and `swift run AgentMeter --self-check` for app-model integration checks. All use offline fixtures; app-model checks use a disposable preferences domain and synthetic providers. `scripts/build.sh` creates the app bundle, renders its icon with AppKit, copies license notices, signs it, and verifies the signature and `Info.plist`. Use `CONFIGURATION=debug bash scripts/build.sh` for a debug build.

## Architecture

| Area | Responsibility |
| --- | --- |
| `Sources/MeterCore` | Shared subscription and quota models, response parsing, freshness policy, currency totals, and version comparison |
| `Sources/MeterProviders` | Local Codex app-server and Claude credential/HTTP adapters |
| `Sources/AgentMeter/AppModel.swift` | Refresh scheduling, local persistence, demo isolation, and manual update checks |
| `Sources/AgentMeter/Views` | Native SwiftUI dashboard, concise menu bar quota panel, subscription management, and settings |
| `Tests/MeterChecks` | Offline checks for core behavior and response handling |
| `Tests/ProviderChecks` | Temporary fake-CLI and credential fixtures for offline adapter checks |
| `Resources` and `scripts` | App metadata, original icon generation, build, test, and release packaging |

Quota adapters return provider readings; the model does not derive billing dates from them. Custom entries are manual. Codex and Claude entries can explicitly switch to manual quota tracking; manual entries skip provider reads and keep their own recorded-at timestamp. The menu bar presents subscription-level remaining quota, reset time, and read status from the same model used by the dashboard.

Keep missing data optional, manual fields visibly identified, credentials out of logs and saved records, and demo mode isolated from real accounts. Currency totals must stay separated by currency. The interface defaults to Simplified Chinese and can switch to English.

## Validation

```bash
bash scripts/test.sh
bash scripts/package.sh --universal
lipo -info dist/AgentMeter.app/Contents/MacOS/AgentMeter
codesign --verify --deep --strict dist/AgentMeter.app
```

CI runs the core checks and universal packaging on macOS 14 and 15. A successful offline check or CI build does not verify access to a real subscription. Live verification requires the account owner's existing official client login and should report only redacted status and quota values. Do not commit credentials, local preference exports, or raw account responses as fixtures.

Before a release, review both interface languages and demo mode in the dashboard and menu bar. Check manual quota windows and timestamps, switching automatic entries to manual, unavailable or stale data, provider login failures, and the manual update action. Menu bar rows must keep missing values, stale readings, and manual records distinct. README screenshots must come from the actual application with sample data visibly identified.

Generate native demo screenshots in both languages with `swift run AgentMeter --render-screenshots docs/images`, including `menu.png` and `menu-zh.png` for the menu panel. The optional `swift run AgentMeter --probe codex` or `--probe claude` path uses the corresponding real local login for a read-only usage check; it is not part of the offline test script or CI.

## Packaging and releases

```bash
bash scripts/package.sh --universal
```

The build targets `arm64-apple-macosx14.0` and `x86_64-apple-macosx14.0`, combines the executables with `lipo`, and writes:

```text
dist/AgentMeter.app
dist/AgentMeter-1.0.1-universal.zip
dist/AgentMeter-1.0.1-universal.zip.sha256
```

The version comes from `Resources/Info.plist`. Download the ZIP and its checksum file into the same folder, then verify them there:

```bash
shasum -a 256 -c AgentMeter-1.0.1-universal.zip.sha256
```

A checksum detects a mismatch with the published file; it does not establish a Developer ID identity. The default signature is ad-hoc. `CODESIGN_IDENTITY` can select an available signing identity locally, but notarization is a separate process that these scripts do not perform. No build step changes Gatekeeper settings.

The **Publish Release** workflow accepts either a pushed `v<version>` tag or a manual `version` input without `v`. The input must match `CFBundleShortVersionString`. For manual runs, GitHub Releases creates the version tag at the selected workflow commit if it does not already exist. An existing tag must point to that commit. Existing releases are preserved; the workflow does not overwrite their assets.

To publish a new version, update `CFBundleShortVersionString` and increment `CFBundleVersion`, review and commit the change, then push the matching tag or run the release workflow. It reruns the checks, packages a universal ZIP and checksum, and publishes them using the workflow's `GITHUB_TOKEN` exposed as `GH_TOKEN`. It requires repository `contents: write` permission.

## Update behavior

The settings action queries `api.github.com/repos/NginxL/AgentMeter/releases/latest` and compares a three-part release version with the bundled version. A newer version opens the repository's release page in the browser. The app does not download assets or replace itself. Replacing the app bundle manually retains the preferences in `io.github.nginxl.AgentMeter`.

## Contributing

Prefer small changes with relevant checks. Update both language versions when behavior changes. Keep documentation tied to actual fields and data sources, and distinguish offline fixture coverage from live provider compatibility.
