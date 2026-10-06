# Darkroom change log

Running list of requested changes and when each one landed.

**How to read it**

- `[ ]` planned · `[~]` in progress · `[x]` done · `[-]` dropped
- Done items end with `→ version · date · commit`.
- Item numbers (e.g. **3.2**) stay fixed, so you can say "do 3.2 next".
- New requests go at the bottom of the current revision, or into a new
  revision section.

---

## Revision v0.2 (requested 2026-10-06)

Ships as app version **1.3.x**, one patch number per batch:
A = 1.3.0 (quick fixes), B = 1.3.1 (pipeline, Polaroid, zoom),
C = 1.3.2 (visual pieces).

### 1. Carousel & navigation

- [x] **1.1 Swipe hitbox:** swiping anywhere on the screen scrolls the
  carousel, not just on the item icon. → 1.3.0 · 2026-10-06 · c8baa37
- [x] **1.2 Gesture deadzone:** add a deadzone for up/down swipes so a
  horizontal swipe doesn't close or open the carousel by accident. → 1.3.0 · 2026-10-06 · c8baa37
- [x] **1.3 Swipe targets:** swiping on the film icon or on the text label at
  the bottom both cycle through the choices. → 1.3.0 · 2026-10-06 · c8baa37
  Works on the camera screen too: swipe the name or film box sideways.
- [x] **1.4 Animation polish:** smooth the jumpy transition between items
  that have tags (grain strength, movie). → 1.3.0 · 2026-10-06 · c8baa37
- [x] **1.5 Alignment:** centre the film stock element properly. → 1.3.0 · 2026-10-06 · c8baa37
- [x] **1.6 Caret placement:** move the small arrow caret next to the film
  name from the left to the centre. → 1.3.0 · 2026-10-06 · c8baa37

### 2. Photo & video previews (film & digital)

- [x] **2.1 Pan vs. swipe:** when zoomed into a photo, panning must not
  trigger swipe-to-next. Applies to film and digital. → 1.3.0 · 2026-10-06 · c8baa37
- [x] **2.2 Film video replay:** film videos won't play again after reaching
  the end (digital videos are fine). → 1.3.0 · 2026-10-06 · c8baa37
  Not reproducible off-device; please confirm on the Pixel.
- [ ] **2.3 Film video thumbnails:** a stylised image of the first frame so
  each reel can be identified. Idea: a print glued to the front of the
  spool. Come up with something that makes physical sense.
- [ ] **2.4 Developing state:** a distinct, stylised look for film videos
  that are still developing.
- [x] **2.5 Share sheet preview:** sharing a video on Android shows only the
  file name. Pass a thumbnail to the share sheet. → 1.3.0 · 2026-10-06 · c8baa37
  Android-side change; please confirm on the Pixel.

### 3. Camera UI & viewfinder

- [ ] **3.1 Mode transition:** replace the Film ↔ Digital fade with a large
  slide: the whole camera slides off and the other slides in. Possibly add a
  "swap device" sound. Remove the slider switch and add another obvious
  control for swapping. *Build a demo first for approval.*
- [ ] **3.2 Motorised zoom:** fixed-rate zoom on dedicated buttons for the 90s
  Camcorder (no pinch). The buttons also work in the other digital cameras.
  Realistic zoom limits per camera. **No zoom at all in Film mode.**
- [ ] **3.3 Zoom indicator:** retro sliding zoom bar overlaid on the camcorder
  screen.
- [ ] **3.4 Zoom buttons always shown:** keep the zoom buttons on every digital
  camera so buttons don't appear or vanish when switching cameras.
- [ ] **3.5 Front camera button:** redesign the switch-camera button; the
  current one is too plain.
- [ ] **3.6 Landscape fixes:** the flash and aspect ratio buttons shouldn't
  stretch or rotate awkwardly. The settings menu, carousel and filters must
  lay out properly when the phone is held sideways.

### 4. Windows 98 mode & darkroom

- [ ] **4.1 Win98 UI scale:** make the Win98 UI bigger, especially the photo
  navigation buttons, for touch. Keep the proportions and the Win98 look.
- [ ] **4.2 Win98 navigation:** no left/right swiping. Add a zoom slider and a
  "Reset Zoom" button; pinch-to-zoom still works.
- [ ] **4.3 Win98 video player:** Win98-style buttons instead of tap to
  play/pause: rewind, fast forward, previous, next, stop, play/pause. Glitchy
  VHS-style artefacts while rewinding and fast-forwarding. Progress slider,
  elapsed/total time, and the other things a player would normally show.
- [ ] **4.4 Win98 metadata:** read the camera type from the photo's
  Exif/metadata and show it at the bottom of the Win98 viewer.
- [ ] **4.5 Floppy drive easter egg:** the camcorder transfers videos by a
  different route than the SD card, worked in through a floppy drive (A:) in a
  way that still makes sense, since a camcorder has no floppy.
- [ ] **4.6 Darkroom progress visual:** replace the plain white square with a
  more immersive progress visual that follows real film development
  (simplified).

### 5. Performance & general

- [x] **5.1 Red square:** remove the unexplained red square at the top of the
  screen. → 1.3.0 · 2026-10-06 · c8baa37
  It was the hidden "prints ready" banner peeking out above the safe area.
- [ ] **5.2 Mode ambience:** add visual touches unique to Film and Digital mode
  that pull you in and match real-world equipment.
- [x] **5.3 Flip phone artwork:** it looks folded backwards. Keep the style,
  fix the orientation. → 1.3.0 · 2026-10-06 · c8baa37
- [x] **5.4 Corkboard loading:** fast scrolling leaves blank spaces that fade
  in slowly. Optimise photo lazy-loading. → 1.3.0 · 2026-10-06 · c8baa37
- [ ] **5.5 Corkboard wall:** the background scrolls with the photos, so you
  slide the whole wall instead of a fixed backdrop. Refine the cartoony cork
  with imperfections that show as you scroll. Better-looking pins.
- [ ] **5.6 Corkboard easter eggs:** more hidden interactions, like Win98's.
  For example: tap a pin → "Would you like to discard this image?" → the photo
  and pin fall off the screen (same effect as the bin button in the preview).

### 6. New feature: Polaroid camera (Film mode)

- [ ] **6.1 Aspect:** viewfinder locked to the Polaroid frame (square).
- [ ] **6.2 Corkboard frame:** shown on the corkboard with an authentic
  Polaroid frame.
- [ ] **6.3 Handwritten note:** type a note at the preview stage; it's drawn in
  a handwritten font on the bottom border.
- [ ] **6.4 Export:** the white border and note are baked into saved and shared
  images.
- [ ] **6.5 Development time:** 20 seconds.
- [ ] **6.6 Darkroom visual:** the Polaroid visibly fades in as it develops.

### 7. New stock / camera pipeline

- [ ] **7.1 Consistent pipeline:** adding a film stock or camera should touch
  as little code as possible. Film and Digital each follow one consistent
  pattern.
- [x] **7.2 Intake form:** a fill-in sheet for each new stock or camera. See
  [`NEW_CAMERA_FORM.md`](NEW_CAMERA_FORM.md). Draft; fields marked *(after
  7.1)* go live once 7.1 lands. → docs only · 2026-10-06
