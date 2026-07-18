# Orbit project instructions

## Localization

- Every user-facing string must be localized in English, Russian, Spanish,
  German, and French.
- Use `L10n` keys in Swift code instead of hardcoded interface text.
- Keep matching keys in all five localization files:
  `en.lproj`, `ru.lproj`, `es.lproj`, `de.lproj`, and `fr.lproj`.
- The app must automatically follow the macOS interface language. Do not add
  an in-app language selector or override `AppleLanguages`.
- English is the fallback language for any unsupported system language.
- Localization includes menus, settings, tooltips, accessibility labels,
  status messages, alerts, and error descriptions visible to the user.
