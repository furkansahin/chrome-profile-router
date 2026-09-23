# App icon

`AppIcon.png` is the full-resolution source with transparent outer margins. The build resizes it to the standard macOS iconset sizes and creates `AppIcon.icns` with `iconutil`.

Created with the built-in image generation tool. The app name is not embedded in the artwork.

The menu-bar counterpart is a monochrome vector silhouette in `Sources/ChromeProfileRouter/MenuBarIcon.swift`. macOS template rendering adapts it to the menu-bar appearance and selection state.

## Generation prompt

Use case: logo-brand
Asset type: a finished macOS app icon for a small utility that routes links between work and personal browser profiles.
Primary request: design an original, polished icon around a single path smoothly separating into two distinct lanes. The app's candidate name is Linklane, but include NO text or letters.
Style: refined native macOS icon with restrained sculptural depth, smooth satin surfaces, crisp clean silhouette, beautiful at small sizes. Keep the app's existing indigo visual identity.
Composition: one centered rounded-square indigo app tile, front-facing orthographic, two bold luminous pale ribbons forming one elegantly split route inside it; a slim negative-space separation makes the two destinations clear. Balanced substantial mark with generous breathing room. Avoid tiny detail, networks of nodes, browser logos, chain-link clichés, road signs, excessive reflections, or busy decorative elements.
Lighting: soft studio highlights, gentle depth, tasteful subtle shadow within the icon.
Output: a single 1024x1024 square PNG app icon, not a mockup or presentation sheet. The rounded-square tile fills about 86% of the canvas width and height with transparent outer margins and genuinely transparent corners; preserve alpha. No solid canvas background, no checkerboard drawn into the image, no captions, no watermark.
