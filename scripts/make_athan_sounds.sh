#!/bin/sh
# Builds the athan alert sounds in Niyat/Resources/Athan from Aladhan's
# recordings (Islamic Network, cdn.aladhan.com; see docs/SOURCES.md).
#
# An iOS alert sound plays for 30 seconds at most, so each file is the
# athan's opening: from where the muezzin starts (after any intro) to the
# breathing pause before 30 seconds, with a short fade. The start times here
# match `Muezzin.startOffset` in Shared/Athan.swift, which the full athan
# skips to when it plays.
#
# Needs ffmpeg (brew install ffmpeg) and afconvert (built into macOS).
# Run with `make athan`.
set -eu

out="Niyat/Resources/Athan"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"

# id  file on the CDN                excerpt start  excerpt end (seconds)
while read -r id file start end; do
    curl -sSfL -o "$work/$id.mp3" "https://cdn.aladhan.com/audio/adhans/$file"
    length=$(echo "$end - $start" | bc)
    fade=$(echo "$length - 0.6" | bc)
    ffmpeg -loglevel error -y -ss "$start" -t "$length" -i "$work/$id.mp3" \
        -af "afade=t=in:d=0.08,afade=t=out:st=$fade:d=0.6" -ac 1 -ar 44100 "$work/$id.wav"
    # IMA4 in a .caf: an alert-sound format, about a quarter of plain PCM's size.
    afconvert -f caff -d ima4 "$work/$id.wav" "$out/athan-$id.caf"
    echo "athan-$id.caf: ${length}s"
done <<'EOF'
alafasy a9.mp3 0.85 19.9
alafasy-dubai a4.mp3 5.95 22.9
alafasy-2 a7.mp3 4.85 21.4
nafees a1.mp3 9.05 26.9
ozcan a2.mp3 7.85 20.9
zahrani a11-mansour-al-zahrani.mp3 0 26.2
EOF
