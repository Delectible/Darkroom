# Store listings and What's new

How Darkroom's store text is kept (CLAUDE.md points here).

## The listing (description, tagline, images)

- **English is the owner's.** He writes and edits the English description
  and tagline himself in the Play Console and App Store Connect. Never
  change or upload English unless he asks. `fastlane/metadata/android/en-AU`
  is only a reference copy of his current text (2026-11-20).
- **Translations live in the repo** so they stay consistent:
  `fastlane/metadata/android/<lang>/` (title, short_description = tagline,
  full_description; `apple_subtitle.txt` where the tagline is over Apple's
  30 characters). Apple gets the same text through `fastlane/apple_listing.py`,
  which maps the language codes.
- **Languages (19):** es-ES, es-419, pt-BR, fr-FR, de-DE, it-IT, ja-JP,
  ko-KR, zh-CN, id, tr-TR, ru-RU, hi-IN, ar, vi, th, pl-PL, nl-NL, uk.
  Add a language when downloads come from a country that speaks it (the
  owner is setting up download-country reports, December 2026).
- **No brand names** in any language ("instant photos", never Polaroid; in
  Chinese not 拍立得).
- When the English changes: he gives the new text; translate every language
  again, then upload.
- **Upload:** only when he asks. Actions > "Play Store listing", `languages`
  = the codes above (space-separated, never English), store `both`. Play
  gets the listing at once; Apple puts it on the version being prepared,
  live with the next "release to iPhone".

## What's new (release notes)

- **One summary per publish**, covering every user-facing change since the
  last production release (not since the last test build). Example: 2.4
  summarised everything since 2.3.0.
- **Short and exciting:** a heading line and 3-5 bullets of what users get.
  Features and improvements they'll notice; no back-end work, no fixes
  lists, no detail. Under Play's 500 characters in every language.
- Written in `fastlane/whatsnew/en-AU.txt` (shown to the owner first), then
  translated into every listing language as `fastlane/whatsnew/<lang>.txt`.
- **Sent on "publish":** `promote-production.yml` (notes on, the default)
  gives Play every language; `appstore-release.yml` gives Apple every
  language (`fastlane/release_notes.py` maps the codes).
- Test builds (internal / TestFlight) still carry `AppInfo.latest`, a
  one-line note of that build's change.
