#!/usr/bin/env python3
"""Download multilingual frequency dictionaries for BESTIE's Word Chain game.

Sources: hermitdave/FrequencyWords (OpenSubtitles-derived frequency lists).
The repository states that its content is CC-BY-SA-4.0; keep attribution when
shipping the resulting database and review the license for your distribution.

The script intentionally does not alter Supabase: BESTIE's current word-game
RPC is server-side and its dictionary table/function definition is not part of
the Flutter project. This script prepares clean, ranked CSV files that can be
loaded into the existing Supabase dictionary table once its schema is confirmed.
"""
from __future__ import annotations

import csv
import io
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "supabase" / "word_data"
BASE_CANDIDATES = (
    "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/{lang}/{lang}_full.txt",
    "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/{lang}/{lang}_50k.txt",
)
LANGS = ("tr", "en", "de", "es", "fr")
MAX_WORDS = 100_000

# Keep game-safe tokens: alphabetic words only, no names with punctuation,
# numbers, URLs, or multi-token phrases.
WORD_RE = re.compile(r"^[\wÀ-ÖØ-öø-ÿĀ-žА-я]+$", re.UNICODE)


def download(lang: str) -> str:
    last_error = None
    for template in BASE_CANDIDATES:
        url = template.format(lang=lang)
        print(f"Downloading {lang}: {url}")
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                return response.read().decode("utf-8", errors="ignore")
        except Exception as exc:
            last_error = exc
    raise RuntimeError(f"Could not download {lang}: {last_error}")


def parse(text: str) -> list[tuple[int, str, int]]:
    result = []
    seen = set()
    rank = 0
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.rsplit(" ", 1)
        word = parts[0].strip().lower()
        try:
            frequency = int(parts[1])
        except (IndexError, ValueError):
            continue
        if not WORD_RE.fullmatch(word):
            continue
        if len(word) < 2 or word in seen:
            continue
        seen.add(word)
        rank += 1
        result.append((rank, word, frequency))
        if len(result) >= MAX_WORDS:
            break
    return result


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for lang in LANGS:
        rows = parse(download(lang))
        path = OUT / f"{lang}_dictionary.csv"
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(("language_code", "word", "frequency_rank", "frequency"))
            writer.writerows((lang, word, rank, frequency) for rank, word, frequency in rows)
        print(f"{lang}: {len(rows):,} words -> {path}")


if __name__ == "__main__":
    main()
