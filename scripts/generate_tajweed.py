#!/usr/bin/env python3
"""Builds Niyat/Resources/Quran/tajweed-hafs.json: tajweed colour marks for the
bundled Tanzil Uthmani text.

Source: cpfair/quran-tajweed (https://github.com/cpfair/quran-tajweed), CC BY 4.0,
built from ReciteQuran.com and the Dar al-Maarifah tajweed masahif. Its
published annotations point into a 2017 copy of the Tanzil text whose encoding
differs slightly from ours, so we run the project's own classifier (its
published decision trees) on our exact text instead. See docs/SOURCES.md for
how the result compares with the published file.

Usage:
    git clone https://github.com/cpfair/quran-tajweed /tmp/quran-tajweed
    python3 scripts/generate_tajweed.py /tmp/quran-tajweed
"""
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEXT = ROOT / "Niyat/Resources/Quran/quran-uthmani.json"
OUT = ROOT / "Niyat/Resources/Quran/tajweed-hafs.json"


def main(repo: Path) -> None:
    quran = json.loads(TEXT.read_text())
    lines = []
    lengths = {}
    for surah in range(1, 115):
        for verse in quran[str(surah)]:
            lines.append(f"{surah}|{verse['verse']}|{verse['text']}")
            lengths[f"{surah}:{verse['verse']}"] = len(verse["text"].strip())

    # The classifier reads its trees from output/rule_trees.
    trees = repo / "output" / "rule_trees"
    if not trees.exists():
        os.symlink(repo / "rule_trees", trees)
    result = subprocess.run([sys.executable, "tajweed_classifier.py"], cwd=repo, input="\n".join(lines) + "\n",
                            capture_output=True, text=True, check=True)
    annotated = json.loads(result.stdout)

    rules = sorted({a["rule"] for ayah in annotated for a in ayah["annotations"]})
    index = {rule: i for i, rule in enumerate(rules)}
    ayat = {}
    for ayah in annotated:
        key = f"{ayah['surah']}:{ayah['ayah']}"
        # [text length in code points, then rule, start, end for each mark]
        flat = [lengths[key]]
        for a in sorted(ayah["annotations"], key=lambda a: (a["start"], a["end"])):
            flat += [index[a["rule"]], a["start"], a["end"]]
        ayat[key] = flat

    OUT.write_text(json.dumps({
        "source": "cpfair/quran-tajweed (CC BY 4.0), classifier run on Tanzil Uthmani as bundled",
        "rules": rules,
        "ayat": ayat,
    }, ensure_ascii=False, separators=(",", ":")))
    print(f"Wrote {OUT} ({OUT.stat().st_size // 1024} KB, {sum(len(v) // 3 for v in ayat.values())} marks)")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve())
