# New stock / camera form

Copy the template below once per stock or camera, fill in what you know, and
send it over. Send as many as you like at once. Plain words are fine: I turn
descriptions into the numbers. Anything left blank gets a sensible default,
and I'll tell you what I picked.

Fields marked *(after 4.5)* need that [`CHANGELOG.md`](CHANGELOG.md) item
to land first; everything else is supported by the pipeline today.

---

## Template

```
=== NEW CAMERA ===

-- Basics --
Name shown in the app:          (e.g. "Gold 200", "2006 Cybershot")
Mode:                           Film / Digital
Shoots:                         Photos / Video
Subtitle (one short line):      (e.g. "Warm, nostalgic everyday colour")
Viewfinder badge:               (e.g. "ISO 200", "5.0MP", "SP")
Modelled on:                    (real stock / camera and year, if any)

-- Frame --
Aspect ratios allowed:          3:2 / 4:3 / 1:1 / 16:9 / other: ___
Default aspect:
Image quality feel:             crisp modern / 2000s digicam / VGA-era low-res

-- The look (describe in words) --
Overall:                        (e.g. "warm, soft contrast, slightly faded")
Colour or black & white:
Shadows:                        (crushed / lifted / tinted ___)
Highlights:                     (roll off softly / clip hard / tinted ___)
Skin tones:
Skies / blues:
Greens / foliage:
Anything distinctive:           (halation glow, light leaks, colour cast…)
Reference photos:               (2-5 real example shots — links or uploads.
                                 The single most useful thing you can send.)

-- Film only --
Grain:                          fine / medium / coarse / heavy
Highlight glow (halation):      none / subtle / strong
Vignette:                       none / subtle / strong
Develop time:                   (default 5 min; Polaroid 600 is 20 s)
Print style:                    plain print / instant (square, written-on border)
Roll or pack:                   (default 36-exposure roll; e.g. "8-shot pack")

-- Digital only --
Date stamp:                     none / orange LED date / phone-style corner /
                                camcorder on-screen clock / new style: ___
File name prefix on SD card:    (4 letters, e.g. DSC0, IMG_, PICT)
Artefacts:                      soft lens / CCD smear on lights / JPEG blocks /
                                pixelated / scanlines / colour bleed / noise
Flash:                          harsh / weak / none
Zoom range & speed:             (e.g. "3x, quick" or "10x, slow motor")
Saves to:                       SD card / floppy / other             *(after 4.5)*

-- Video only --
Frame rate feel:                (e.g. 18 fps home movie, 30 fps tape)
Max clip length:
Sound:                          yes / no

-- Picker artwork --
Object shown:                   film box / canister / camera body / other
Colours & markings:             (no real logos; describe the feel)
Product shot reference:         (optional link or photo)

-- Anything special --
(unique buttons, notes, sounds, easter eggs, behaviour that differs
 from the other cameras)
```

---

## What I do with a form

So you know what a "clean" addition looks like:

1. **Catalog entry:** name, badge, aspects, quality, output size, develop
   time, print style, roll/pack and zoom in
   `lib/features/cameras/domain/camera_catalog.dart`.
2. **Look:**
   - Film: a `FilmProfile` in `lib/core/processing/film/film_profile.dart`.
     It drives the live preview, stills and video from one colour LUT.
   - Digital: a `LookSpec` on the catalog entry, using one of the existing
     shader styles (CCD, JPEG/pixel, VHS).
3. **Artwork:** a 3D render made with `tool/render/` and added to
   `assets/artwork/`.
4. **Checks:** `test/catalog_contract_test.dart` checks every entry is
   complete (look, artwork, aspects, zoom, file names); the shader contract
   test covers the look. I add a test if the camera brings new behaviour.
5. **Log:** version bump, a line in Help > About, and a tick in
   `CHANGELOG.md`.

Anything outside these five steps (a new shader style, a new print frame, a new
storage route) is a feature, not just a new camera. I'll flag it before building.
