# Chrome Profile Router

A small native macOS menu-bar app that sends links to the right Chrome profile, with a focused Chrome-only feature set.

- Choose one **Work profile** and the apps whose links should open there automatically.
- **Slack** and **iTerm** are included initially; add or remove source apps in Settings.
- Links from other apps show a compact picker with profile avatars and keyboard shortcuts.
- Open any discovered Chrome profile directly from the menu-bar menu.
- Browsing inside Chrome continues normally.

## Build and install

Requires macOS, a Swift 6 toolchain, and the macOS SDK. The deployment target is macOS 14; integration testing so far has been on macOS 27. There are no external package dependencies.

```sh
bash scripts/test.sh
bash scripts/build.sh
bash scripts/install.sh
```

The scripts prefer Command Line Tools when installed. Set `DEVELOPER_DIR` to use a specific Xcode installation. The build produces `dist/Chrome Profile Router.app` with a local ad-hoc signature. The installer copies it to `/Applications`, registers it, and opens Settings. Reinstalling saves a backup of the previous app under `dist/`.

This repository builds a local app. Developer ID signing, notarization, and downloadable releases are not configured.

## Setup

1. Select your **Work profile** from the Chrome profile dropdown.
2. In **Open in Work**, add source apps or remove them using the minus button.
3. Click **Enable link handling** and accept the macOS default-browser prompt if shown.
4. Set **Launch at login** as desired, then close Settings.

If profile discovery needs permission, use **Allow Chrome profiles…** to select `~/Library/Application Support/Google/Chrome`.

## Picker

Click a profile, press its number (1–9), or use the arrow/Tab keys followed by Return. Escape or an outside click cancels pending picker choices. Repeated links stay separate; automatic Work links queued behind a picker retain their destination.

The menu-bar icon also lists your Chrome profiles above Settings and Quit. Select a profile to open it directly. This does not change your Work profile or routing rules.

The app stores the Work selection by profile directory identifier, so renaming a profile preserves the mapping. If the destination disappears, the app asks again instead of silently choosing another profile.

## Disable routing

Choose Google Chrome as the default browser in System Settings. Disable **Launch at login** in the app and quit it. Quitting alone leaves the default-browser association in place, so the next external link can launch the router again.

## Privacy and scope

The app reads Chrome profile metadata and local avatars. It does not read browsing history, cookies, passwords, or page contents. Pending URLs exist only in memory. There is no telemetry, network client, clipboard monitoring, account, or sync service.

Only standard Google Chrome is supported. There are no website rules, browser extensions, private-mode destinations, native-app destinations, URL cleanup, or automatic updates. Chrome's profile metadata and launch arguments are implementation details that may change across browser versions.

## Development

- `Sources/RouterCore`: routing, profile parsing, source-app preferences, and request queue.
- `Sources/ChromeProfileRouter`: macOS URL events, Chrome launch, picker, and Settings.
- `Tests/RouterCoreTests`: focused automated tests using Swift Testing.
- [SPEC.md](SPEC.md): behavior and design decisions.
- [VERIFICATION.md](VERIFICATION.md): validation coverage and limitations.

## License

[MIT](LICENSE).
