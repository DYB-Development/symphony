# Coding Style Preferences

- Prefer simple labels (e.g. "Create", "Save") over resource-specific ones
- Mobile-first — primary UI is often a native webview
- Any page, form, script or stylesheet that a Hotwire Native iOS app shows has to work in that app's web view: it loads on Turbo visits, holds up on a phone connection, and uses nothing the iOS web view lacks
- Keep solutions simple and focused; avoid over-engineering
- No inline forms: a form goes on a page dedicated to that form, and the only forms that sit inside another page are a search filter and a selection form inside a section of the settings page, since a person opens the settings page to change a setting
