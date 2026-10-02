#!/bin/sh
# Downloads Niyat's built-in Qur'an recitation model into the app's resources.
# It is 166 MB, too big for git, so `make` fetches it before Xcode builds (and
# keeps it after that). Model: TheGreatQuran/QuranKarim-SpeechToText-onnxModel
# on Hugging Face, CC BY 4.0 (credited in About & credits).
set -e
cd "$(dirname "$0")/.."
DIR=Niyat/Resources/RecitationModel
BASE=https://huggingface.co/TheGreatQuran/QuranKarim-SpeechToText-onnxModel/resolve/main
mkdir -p "$DIR"

# fetch <file on Hugging Face> <name in the app> <smallest believable size in bytes>
fetch() {
    if [ -f "$DIR/$2" ] && [ "$(wc -c < "$DIR/$2")" -ge "$3" ]; then
        return
    fi
    echo "Downloading the recitation model: $1"
    curl -fL --retry 3 --progress-bar -o "$DIR/$2.part" "$BASE/$1"
    size=$(wc -c < "$DIR/$2.part")
    if [ "$size" -lt "$3" ]; then
        rm -f "$DIR/$2.part"
        echo "error: $1 downloaded as only $size bytes. Check your connection and run 'make model' again." >&2
        exit 1
    fi
    mv "$DIR/$2.part" "$DIR/$2"
}

fetch qurankarim-fastconformer-q8.onnx qurankarim-fastconformer-q8.onnx 150000000
fetch tokens.txt recitation-model-tokens.txt 5000

lines=$(wc -l < "$DIR/recitation-model-tokens.txt")
if [ "$lines" -lt 1000 ]; then
    echo "error: recitation-model-tokens.txt has only $lines lines (expected 1025)." >&2
    exit 1
fi
