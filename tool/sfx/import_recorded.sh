#!/usr/bin/env bash
# Recorded sounds (everything else in assets/sfx is made by make_sfx.py).
# All CC0 (public domain, no credit needed; noted here anyway):
#  * page turns: "80 CC0 RPG SFX" by rubberduck, book_01..04
#    https://opengameart.org/content/80-cc0-rpg-sfx
#  * studio snap: "Camera" by themightyglider (a shutter, rearranged from archive.org's
#    "Camera Shutter Sound", CC0) https://opengameart.org/content/camera
# Trimmed to start on the sound, page turns pitched two ways, cut short with a fade, made mono and set
# quiet like the rest (loudness in LUFS below). Needs ffmpeg, curl, unzip.
# Run from the repo root: tool/sfx/import_recorded.sh
set -euo pipefail
out=assets/sfx
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -sL -o "$tmp/rpg.zip" https://opengameart.org/sites/default/files/80-CC0-RPG-SFX_0.zip
curl -sL -o "$tmp/photo.ogg" https://opengameart.org/sites/default/files/photo.ogg
(cd "$tmp" && unzip -oq rpg.zip)

# in, out, longest (s), loudness (LUFS): cut, then measured and set
prep() {
  local fade cut="$tmp/cut.wav" now
  fade=$(awk "BEGIN{print ($3 > 0.12) ? $3 - 0.12 : 0}")
  ffmpeg -v error -y -i "$1" -af "silenceremove=start_periods=1:start_threshold=-45dB,highpass=f=90,\
atrim=0:$3,afade=t=out:st=$fade:d=0.12,aresample=44100" -ac 1 -c:a pcm_f32le "$cut"
  now=$(ffmpeg -v info -i "$cut" -af ebur128 -f null - 2>&1 | awk '/^ *I:/{v=$2} END{print v}')
  ffmpeg -v error -y -i "$cut" -af "volume=$(awk "BEGIN{print $4 - ($now)}")dB" -c:a pcm_s16le "$2"
}

# each take twice, a touch lower and higher (pitch and speed together, as
# a page turned a little slower or faster would): 8 to shuffle between
rm -f "$out"/page_turn_*.wav
for i in 1 2 3 4; do
  prep "$tmp/book_0$i.ogg" "$tmp/take.wav" 0.6 -51
  ffmpeg -v error -y -i "$tmp/take.wav" -af "asetrate=44100*0.94,aresample=44100" -c:a pcm_s16le "$out/page_turn_${i}a.wav"
  ffmpeg -v error -y -i "$tmp/take.wav" -af "asetrate=44100*1.06,aresample=44100" -c:a pcm_s16le "$out/page_turn_${i}b.wav"
done
prep "$tmp/photo.ogg" "$out/studio_snap.wav" 0.9 -48
ls -la "$out"/page_turn_*.wav "$out"/studio_snap.wav
