#!/usr/bin/env python3
"""Extract Tanzil's reading signs without modifying the bundled Quran text.

Download XML from https://tanzil.net/pub/download/index.php with marks=true,
sajdah=true, outType=xml, agree=true; quranType is uthmani, uthmani-min or
simple. Pass the three files in that order. Every verse is checked verbatim
against its existing edition after removing only the downloaded reading signs.
"""
import collections
import hashlib
import json
import pathlib
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
SIGNS = set('ۖۗۘۙۚۛۜ۩')
EDITIONS = [('uthmani', 'quran-uthmani'), ('uthmaniMinimal', 'quran-uthmani-min'), ('imlaei', 'quran-imlaei')]

def extract(xml_path, filename):
    bundled = json.loads((ROOT / 'Niyat/Resources/Quran' / (filename + '.json')).read_text())
    verses = {}
    count = 0
    for surah in ET.parse(xml_path).getroot().findall('sura'):
        s = int(surah.attrib['index'])
        for aya in surah.findall('aya'):
            v = int(aya.attrib['index'])
            text = aya.attrib['text']
            bare = ' '.join(piece for piece in text.split() if not set(piece) <= SIGNS)
            full = (aya.attrib.get('bismillah', '') + ' ' + bare).strip()
            assert full == bundled[str(s)][v - 1]['text'], f'Text mismatch: {filename} {s}:{v}'
            signs = {}
            word = -1
            for piece in text.split():
                if not set(piece) <= SIGNS:
                    word += 1
                else:
                    assert word >= 0
                    signs[str(word)] = signs.get(str(word), '') + piece
            if signs:
                verses[f'{s}:{v}'] = signs
            count += 1
    assert count == 6236
    return verses

if __name__ == '__main__':
    assert len(sys.argv) == 4, 'Pass uthmani.xml uthmani-min.xml simple.xml'
    data = {}
    for (edition, filename), source in zip(EDITIONS, sys.argv[1:]):
        data[edition] = extract(source, filename)
        counts = collections.Counter(c for words in data[edition].values() for signs in words.values() for c in signs)
        assert counts['۩'] == 15, counts
        print(edition, dict(counts))
    output = ROOT / 'Niyat/Resources/Quran/reading-signs.json'
    output.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')) + '\n')
    print('SHA-256:', hashlib.sha256(output.read_bytes()).hexdigest())
