# Chrome Profile Router — specification

## Purpose

A native macOS menu-bar app that routes external web links to Chrome profiles, with a compact profile picker.

| Source | Behavior |
| --- | --- |
| An app in the Work list | Open automatically in the chosen Work profile. |
| Another or unknown app | Show the profile picker. |
| Ordinary navigation inside Chrome | Stay under Chrome's control. |

Slack and iTerm are initial Work sources. The owner can add or remove installed application bundles. All configured sources share one Work profile. An empty source list disables automatic routing.

## Routing

1. Accept HTTP and HTTPS URLs delivered through macOS's default-browser mechanism.
2. Resolve the Apple-event sender's process to its bundle identifier. Never guess from the frontmost app.
3. Match that exact identifier against the configured Work app list.
4. Automatically open in Work when both the source and destination are valid; otherwise show the picker.

If Work is unconfigured or unavailable, explain why a choice is needed. Store the destination by Chrome profile directory ID so renaming preserves the mapping. Never silently fall back to a different profile or recreate a deleted profile.

Preserve the received URL, including query strings, encoded characters, and fragments. Pass it as an argument directly to the chosen Chrome application, without shell interpolation or routing back through the system default browser. Unsupported or malformed URLs show a recovery state.

Chrome may reuse a window or create one according to its normal behavior. The app does not force a new window or private mode. Ordinary Chrome navigation is never intercepted. A URL Chrome explicitly sends through macOS is evaluated as an external request.

## Picker

- A small rounded native floating panel near the cursor, constrained to the screen's usable bounds.
- A horizontal row of profile cards with local avatars or initials, display names, and number shortcuts.
- A quiet header with the destination hostname and known source app; no query strings in the normal header.
- System light/dark appearance, accessible labels, visible selection, and horizontal scrolling when needed.
- Click or press 1–9 to choose. Arrow keys and Tab/Shift-Tab move selection; Return opens it.
- Escape or an outside click cancels pending picker requests.
- Profile order and shortcuts remain fixed while a picker is visible.

Each incoming click remains a separate request, including identical URLs. Process requests in arrival order. Show one picker at a time with a pending count. A choice applies to one request. Automatic Work links arriving behind a picker wait their turn. Cancelling clears picker requests while retaining deferred automatic requests. Pending URLs are discarded on quit.

## Settings

- **Work profile:** an existing Chrome profile or Always ask.
- **Open in Work:** an editable source-app list, initially Slack and iTerm. Add apps uses a native application chooser; duplicates are excluded by bundle ID.
- **Link handling:** active/inactive status and a user-initiated default-browser setup action.
- **Launch at login:** macOS login-item registration, with actual enabled/approval status.
- Profile-access and refresh controls when needed.

Do not reclaim the default-browser association automatically. Changing the system default browser disables routing. Launching the app from Finder opens Settings; normal operation has a menu-bar item and no persistent Dock icon.

The menu-bar menu lists discovered Chrome profiles above Settings and Quit. Selecting one launches that profile directly without requiring a pending URL or changing routing settings. Revalidate the profile before launch and show recovery if it is unavailable. Keep the visible menu order stable while refreshing discovery for its next opening.

## Profiles and errors

Read standard Chrome profile metadata and local avatar files only. Refresh off the main thread before routing, and revalidate the chosen profile before dispatch. Exclude Guest, System, omitted, and missing profiles. Disambiguate duplicate display names with directory IDs. Unreadable avatars fall back to initials.

Unreadable metadata, missing Chrome/profiles, invalid URLs, and launch failures keep the request available with appropriate Retry, Copy Link, Settings, and Cancel recovery. Offer remaining valid profiles when possible.

## Implementation

Swift, AppKit, and SwiftUI with no external dependencies. Declare HTTP/HTTPS handlers and install an Apple-event handler early enough to receive the URL that launches the app. Use NSWorkspace to launch Chrome with an explicit profile-directory argument and a new application instance; Chrome forwards to its existing browser process. Let Chrome raise its destination window and wait for the handoff before showing the next queued picker.

Local preferences store the Work profile, source apps, and any folder-access bookmark. The macOS login service manages startup registration. There is no network service or URL history.

## Scope

Chrome only, using its standard user-data folder. No other browser destinations, domain/regex rules, per-workspace routing, extensions, URL transformation, private-mode destinations, native-app destinations, sync, accounts, analytics, automation interfaces, or updater.

## Validation

Core checks cover source matching and changes, profile identity and parsing, URL preservation, and queue semantics. macOS integration checks cover real source-app clicks, warm/cold launches, destination profile selection, picker focus, cancellation, and unchanged Chrome navigation. See [VERIFICATION.md](VERIFICATION.md) for observed coverage.

The approximate 150 ms picker/dispatch target excludes Chrome launch and page loading and has not been measured. Light mode, accessibility, and multi-display/full-screen behavior require broader validation before claiming comprehensive compatibility.
