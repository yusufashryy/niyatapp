#!/usr/bin/env python3
"""Fetch the English hadiths of HadeethEnc.com (the Encyclopedia of Translated
Prophetic Hadiths, by the same centre as QuranEnc) and write the authentic ones
into the app (`make hadith`).

Every hadith in the encyclopedia was chosen and graded by its scholars, with
the grading scholar's verdict in Arabic (grade_ar). Niyat keeps only hadiths of
the Prophet (peace be upon him) graded Sahih (authentic) or Hasan (good), the
two grades scholars accept as proof. Left out, to stay on the safe side:
- any grade that mentions weakness (ضعيف);
- sayings of Companions rather than of the Prophet (موقوف, الآثار);
- hadiths authentic only "except" a part (دون ...);
- notes instead of a verdict (no grading found, a grading only relayed, or a
  comment on the narrators rather than the hadith).
The text, explanation and lessons are kept exactly as published (only
surrounding white space is trimmed).

Output: Niyat/Resources/Hadith/hadith-en.hadith, raw-DEFLATE JSON:
  {"version", "topics": [[id, parent or 0, title, count]],
   "hadiths": [{"id","title","text","arabic","source","grade","level","explanation","lessons","topics"}]}

Usage: python3 scripts/build_hadith.py [--from DIR]
  DIR holds hen_categories.json and hen/<id>.json saved from the API.
"""
import datetime
import glob
import json
import os
import subprocess
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Niyat", "Resources", "Hadith", "hadith-en.hadith")
API = "https://hadeethenc.com/api/v1"

EXCLUDE = ["ضعيف", "موقوف", "الآثار", "دون", "لم نجد", "ولم يتعقبه", "رجاله رجال"]


def level(grade_ar):
    """'sahih', 'hasan', or None to leave the hadith out."""
    grade = (grade_ar or "").strip()
    if not grade or any(word in grade for word in EXCLUDE):
        return None
    if "حسن" in grade:
        return "hasan"
    if "صح" in grade:  # صحيح, صحيحة, صحيحان
        return "sahih"
    return None


def get(path):
    raw = subprocess.run(["curl", "-sf", "--retry", "3", "-m", "60", API + path],
                         check=True, capture_output=True).stdout
    return json.loads(raw)


def load(folder):
    if folder:
        topics = json.load(open(os.path.join(folder, "hen_categories.json"), encoding="utf-8"))
        hadiths = [json.load(open(f, encoding="utf-8")) for f in glob.glob(os.path.join(folder, "hen", "*.json"))]
        return topics, hadiths
    topics = get("/categories/list/?language=en")
    ids = set()
    for topic in (t for t in topics if t["parent_id"] is None):
        page = 1
        while True:
            listing = get(f"/hadeeths/list/?language=en&category_id={topic['id']}&page={page}&per_page=500")
            ids |= {h["id"] for h in listing["data"]}
            if page >= int(listing["meta"]["last_page"]):
                break
            page += 1
    return topics, [get(f"/hadeeths/one/?language=en&id={i}") for i in sorted(ids, key=int)]


def main():
    folder = sys.argv[sys.argv.index("--from") + 1] if "--from" in sys.argv else None
    topics, raw = load(folder)
    hadiths, left_out = [], []
    for h in sorted(raw, key=lambda h: int(h["id"])):
        kind = level(h.get("grade_ar"))
        if kind is None or not h.get("hadeeth", "").strip():
            left_out.append((h["id"], h.get("grade_ar")))
            continue
        hadiths.append({
            "id": int(h["id"]),
            "title": h["title"].strip(),
            "text": h["hadeeth"].strip(),
            "arabic": (h.get("hadeeth_ar") or "").strip(),
            "source": (h.get("attribution") or "").strip(),
            "grade": (h.get("grade") or "").strip(),
            "level": kind,
            "explanation": (h.get("explanation") or "").strip(),
            "lessons": [x.strip() for x in h.get("hints") or [] if x.strip()],
            "topics": [int(c) for c in h.get("categories") or []],
        })
    used = {t for h in hadiths for t in h["topics"]}
    counts = {}
    for h in hadiths:
        for t in h["topics"]:
            counts[t] = counts.get(t, 0) + 1
    by_id = {int(t["id"]): t for t in topics}
    # Keep topics that hold hadiths, and their parents.
    keep = set()
    for t in used:
        while t in by_id and t not in keep:
            keep.add(t)
            t = int(by_id[t]["parent_id"] or 0)
    out = {
        "version": "HadeethEnc.com, fetched " + datetime.date.today().isoformat(),
        "topics": [[i, int(by_id[i]["parent_id"] or 0), by_id[i]["title"].strip(), counts.get(i, 0)] for i in sorted(keep)],
        "hadiths": hadiths,
    }
    encoded = json.dumps(out, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    packed = compressor.compress(encoded) + compressor.flush()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(packed)
    sahih = sum(1 for h in hadiths if h["level"] == "sahih")
    print(f"wrote {OUT}: {len(hadiths)} hadiths ({sahih} sahih, {len(hadiths) - sahih} hasan), "
          f"{len(out['topics'])} topics, {len(packed) // 1024} KB; left out {len(left_out)}:")
    for item in left_out:
        print("  ", item[0], (item[1] or "").replace("\n", " ")[:90])


if __name__ == "__main__":
    main()
