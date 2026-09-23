# Verification

## Automated checks

The Swift Testing suite contains **17 passing tests**, covering:

- Work routing for Slack and iTerm; exact bundle-ID matching; adding and removing source apps.
- Missing preferences versus an explicitly empty source list.
- Unknown sources, invalid URLs, unavailable profiles, and recovery routing.
- Chrome profile filtering, names, duplicate names, renaming, and stable IDs.
- Exact URL argument preservation and invalid profile-directory rejection.
- Request ordering, repeated clicks, and cancellation that preserves deferred automatic requests.

Run with `bash scripts/test.sh`. The local release build and ad-hoc signing completed successfully.

## Integration checks

Development checks used macOS 27.0 and Chrome 152.0.7977.83 on Apple Silicon.

Verified during implementation:

- A real Slack link opened once in Work while personal Chrome was active, without a picker.
- Slack launched the stopped router, and also started fully stopped Chrome in Work.
- Unmatched links showed the picker; number keys and profile-card selection opened the requested destination.
- Encoded URL components, query parameters, and fragments were preserved.
- Repeated incoming links remained distinct; keyboard selection and queue cancellation worked.
- In-page link clicks stayed in both personal and work Chrome without router UI.
- Picker dark appearance and native accessibility profile labels were inspected.
- Settings preserved the chosen profile and displayed the editable source list, active link handling, and enabled login registration.
- The owner confirmed a real iTerm link click opened in Work.
- The installed menu-bar menu listed all discovered profiles above Settings and Quit. Clicking a profile opened the matching Chrome profile, confirmed through Chrome's profile menu.
- The Tabitat rename built and installed successfully. macOS resolved both HTTP and HTTPS to `/Applications/Tabitat.app`; the existing Work profile preference remained saved under the unchanged bundle identifier.

Checks were performed across development builds; the complete integration suite has not been repeated on every subsequent revision.

## Remaining coverage

Full VoiceOver navigation, light appearance, every display edge/full-screen combination, actual login/logout, the complete Add apps file-dialog interaction, and the performance target have not been exhaustively exercised. Profile deletion/corruption and launch-error handling use isolated tests rather than changes to a real browser profile. Older supported macOS versions have not been integration-tested.

Build artifacts, personal profile screenshots, and machine-specific GUI automation helpers are excluded from the repository.
