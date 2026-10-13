#!/usr/bin/env python3
"""Prepare language-specific word-chain dictionaries for Bestie.

The production Word Chain RPC is intentionally not overwritten because its
live definition/table is not present in this upload. This tool prepares
normalized 50k frequency lists for the existing production dictionary.

Source:
https://github.com/hermitdave/FrequencyWords
Content license: CC BY-SA 4.0.
"""
from pathlib import Path
from urllib.request import urlopen
import csv
import re
import unicodedata

LANGUAGES = ("tr", "en", "de", "es", "fr")
BASE = "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/{lang}/{lang}_50k.txt"

def normalize(value: str) -> str:
    value = unicodedata.normalize("NFKD", value.lower().strip())
    value = value.replace("ı", "i").replace("ß", "ss")
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    return re.sub(r"[^a-z0-9äöüéèêëàâîïôùûçñ]", "", value)

def prepare(out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for lang in LANGUAGES:
        url = BASE.format(lang=lang)
        with urlopen(url, timeout=30) as response:
            raw = response.read().decode("utf-8")
        rows = {}
        for line in raw.splitlines():
            parts = line.split()
            if not parts:
                continue
            word = parts[0].strip()
            if not word or not any(ch.isalpha() for ch in word):
                continue
            normalized = normalize(word)
            if not normalized or len(normalized) < 2:
                continue
            rows.setdefault(normalized, word)
        path = out_dir / f"{lang}_word_dictionary.csv"
        with path.open("w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["language_code", "word", "normalized_word"])
            for normalized, word in sorted(rows.items()):
                writer.writerow([lang, word, normalized])
        print(f"{lang}: {len(rows)} words -> {path}")

if __name__ == "__main__":
    prepare(Path("generated"))
