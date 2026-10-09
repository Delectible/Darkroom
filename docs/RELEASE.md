# Release roadmap

Where Darkroom stands on the way to a public release on Google Play and
the App Store. Tick items as they land (`[x]`), note who does what (G =
Gabe in a console / on a phone, C = Claude in the repo).

## 1. Polish for a first public version

- [x] **Trademark pass** (1.4.3): films are Vivid 100, Portrait 400,
  Classic 400, Instant 600 and Super 8 (a format name); Minefield instead
  of Minesweeper; "Darkroom 98" instead of Windows 98 in our own text and
  the store listing. Keep new names and listing text brand-free.
- [ ] Bug bash on the Pixel 9 Pro and the Galaxy S10+ (older GLES phone):
  every screen, every camera, film develop, save / share, Win98 copies.
  Watch Help > Crash Reports. (G tests, C fixes)
- [ ] Performance check on the S10+: viewfinder frame rate per camera,
  corkboard scroll, swap animation. (G, C)
- [ ] Accessibility basics: screen-reader labels on the main buttons, large
  text doesn't break the Win98 dialogs. (C)
- [~] 3D bodies (1.5, 2026-10-08: the whole body and every control
  rendered in Blender; 3D on by default, Settings switch for the classic
  look); 1.6 renders each camera whole, turned every 3 degrees for the
  swap. Shipped to internal testing; G checks it on the Pixel and S10+.
- [~] Landscape for the corkboard, projector and Darkroom 98 (1.5). (G checks)
- [ ] Store screenshots: 4-8 phone shots (1080x1920 or larger) of the best
  moments: viewfinder, darkroom, corkboard, projector, Win98, picker. (C
  can stage them from the screen tests; G can take real ones)

## 2. Google Play

- [x] App created (`com.dingo.darkroom`), internal testing from CI.
- [x] Store listing basics (title, descriptions, icon, feature graphic),
  synced from `fastlane/metadata/android/en-AU/`.
- [x] Privacy policy URL, Data safety ("no data collected"), Advertising ID
  (none), ads (none).
- [x] Closed testing track + Google Group, `promote-closed.yml` button.
- [ ] Content rating (IARC questionnaire) and Target audience: confirm done
  in App content. (G)
- [ ] Screenshots uploaded (from section 1). (G / C via fastlane)
- [ ] **12+ testers opted in to closed testing for 14 days in a row**
  (Google's rule for new personal developer accounts). Then Dashboard >
  "Apply for production access" (a short questionnaire about the test). (G)
- [ ] Optional: open testing (anyone can join from the store page).
- [ ] Production release with a staged rollout (e.g. 20%, then 100%). (G)
- [ ] Monetization (later): free download + one-time Pro unlock is the plan
  on the table. Needs a payments profile in Play Console and Play Billing in
  the app. A free app can't later become a paid download, but in-app
  purchases can be added any time.

## 3. App Store (iPhone)

- [ ] First proper run on Gabe's iPhone (sideloaded .ipa): camera, film
  develop while closed, notifications, save / share, Win98. Fix what breaks.
  (G tests, C fixes)
- [ ] Apple Developer Program membership (US$99 / A$149 a year): needed
  for TestFlight and the App Store. (G)
- [ ] App ID `com.dingo.darkroom` and signing for CI: an App Store Connect
  API key as repo secrets; CI signs and uploads builds to TestFlight from
  the macOS runner (instead of the unsigned .ipa). (G creates the key, C
  wires CI)
- [ ] App Store Connect listing: name, subtitle, description, keywords,
  support + privacy URLs, screenshots (6.9" and 6.5" iPhone), age rating,
  App Privacy = "Data Not Collected". iPhone only (no iPad) to start. (G / C
  drafts the text)
- [ ] Info.plist: permission texts reviewed; `ITSAppUsesNonExemptEncryption`
  = false (no export paperwork). (C)
- [ ] TestFlight: internal testers, then external testers (needs a light
  beta review). (G)
- [ ] App Review submission, then release. (G)

## Log

- 2026-10-08: closed testing track created, first promotion (build 55).
