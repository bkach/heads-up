# Contributing

Thanks for helping improve Heads Up.

## Development

1. Use a Mac running macOS 14 or later with Xcode or the Xcode Command Line Tools installed.
2. Make a focused change.
3. Run `./build.sh`; warnings are treated as errors and the logic tests run first.
4. Exercise affected AppKit controls with pointer clicks, not only accessibility actions.
5. Do not commit `build/`, `dist/`, credentials, exported calendar data, or local preferences.

## Design principles

- Keep calendar data on the user's Mac.
- Prefer Apple system frameworks over third-party dependencies.
- Make failures and filtering visible rather than silently dropping reminders.
- Preserve the compact native menu-bar interaction and full-screen alert behavior.
- Add a focused test for parsing, filtering, scheduling, or persistence changes.

## Pull requests

Describe the user-visible behavior, the validation performed, and any privacy or compatibility
impact. Screenshots are useful for UI changes. Keep unrelated cleanup in a separate pull request.
