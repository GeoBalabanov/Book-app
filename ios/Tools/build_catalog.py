#!/usr/bin/env python3
"""Builds Lexi's bundled Project Gutenberg catalogue.

Input:  pg_catalog.csv.gz, Project Gutenberg's offline catalogue, from
        https://www.gutenberg.org/cache/epub/feeds/pg_catalog.csv.gz
        (or the mirror https://gutenberg.pglaf.org/cache/epub/feeds/pg_catalog.csv.gz).
Output: ios/Lexi/Resources/gutenberg-catalog.bin, raw-DEFLATE-compressed text
        that Foundation's NSData.decompressed(using: .zlib) reads directly.

Format (UTF-8, one book per line, tab-separated):
    id  title  author  categories  rank
categories: comma-separated indexes into the CATEGORIES list (first line of the file).
rank: lower is more prominent (curated popular list first, then classic shelves).

Usage (from the repo root):
    python3 ios/Tools/build_catalog.py path/to/pg_catalog.csv.gz
"""
import csv
import gzip
import re
import sys
import zlib
from pathlib import Path

# Genre shelves shown in the app (Gutenberg "Category: …" bookshelves).
CATEGORIES = [
    "Novels", "Classics of Literature", "British Literature", "American Literature",
    "Adventure", "Science-Fiction & Fantasy", "Crime, Thrillers and Mystery", "Romance",
    "Historical Novels", "Short Stories", "Poetry", "Plays/Films/Dramas", "Humour",
    "Children & Young Adult Reading", "Mythology, Legends & Folklore", "Philosophy & Ethics",
    "Biographies", "Essays, Letters & Speeches", "Travel Writing", "Religion/Spirituality",
    "Politics", "History - Ancient", "History - Modern (1750+)", "Science - Biology",
]

# Well-known titles, most-read first (checked against the catalogue below).
POPULAR = [
    1342, 84, 11, 2701, 1661, 64317, 98, 345, 2554, 174, 1260, 768, 5200, 1080, 76, 74,
    120, 1232, 43, 35, 36, 164, 1184, 1257, 2600, 1400, 46, 219, 158, 161, 105, 1727,
    6130, 1513, 1524, 1533, 844, 55, 16, 113, 514, 45, 28054, 2638, 600, 4217, 205,
    2814, 2852, 244, 863, 1155, 932, 209, 236, 1837, 3825, 5230, 159, 103, 18857, 829,
    2591, 1497, 2680, 3207, 1998, 4363, 132, 7370, 34901, 2009, 3296, 8800, 1250, 20203,
    16328, 25344, 1952, 1322, 3600, 4300, 215, 1023, 766, 730, 580, 786, 2097, 41,
    2148, 1063, 1064, 2500, 160, 23, 61, 3090, 62, 60, 1251, 2591, 408, 135, 1399, 3268,
]

TITLES = ("emperor", "king", "queen", "saint", "pope", "graf", "baron", "lord", "sir", "count", "duke", "of ")

def display_author(field: str) -> str:
    """'Wells, H. G. (Herbert George), 1866-1946; …' → 'H. G. Wells'."""
    first = field.split("; ")[0]
    first = re.sub(r"\s*\[[^\]]*\]", "", re.sub(r"\s*\([^)]*\)", "", first))
    parts = [p.strip() for p in first.split(",") if p.strip()]
    # Drop dates and lifespans ("1866-1946", "751? BCE", "active 6th century B.C.").
    parts = [p for p in parts if not re.search(r"\d|BCE|B\.C\.|active|approximately|century", p)]
    if not parts:
        return ""
    if parts[0].lower().startswith("various"):
        return "Various"
    last = parts[0]
    if len(parts) == 1:
        return last
    given = parts[1]
    if given.lower().startswith(TITLES) or given[:1].islower():
        return last
    if last in given:
        return given
    return f"{given} {last}"

def main(src: str) -> None:
    rows = csv.DictReader(gzip.open(src, "rt", encoding="utf-8"))
    books = {}
    for r in rows:
        if r["Type"] != "Text" or "en" not in r["Language"].split("; "):
            continue
        book_id = int(r["Text#"])
        title = re.sub(r"\s+", " ", r["Title"]).strip()
        author = display_author(r["Authors"])
        shelves = r["Bookshelves"].split("; ")
        cats = [CATEGORIES.index(s[10:]) for s in shelves if s.startswith("Category: ") and s[10:] in CATEGORIES]
        classic = any(s in shelves for s in ("Best Books Ever Listings", "Harvard Classics", "Category: Classics of Literature"))
        books[book_id] = [title, author, cats, 2 if classic else 3]

    missing = [i for i in POPULAR if i not in books]
    if missing:
        print("popular IDs not in the English catalogue:", missing, file=sys.stderr)
    for rank, i in enumerate(dict.fromkeys(POPULAR)):
        if i in books:
            books[i][3] = 1 + rank / 1000  # keeps curated order inside rank 1

    lines = ["\t".join(CATEGORIES)]
    for book_id, (title, author, cats, rank) in sorted(books.items(), key=lambda kv: (kv[1][3], kv[0])):
        clean = lambda s: s.replace("\t", " ").replace("\n", " ")
        lines.append(f"{book_id}\t{clean(title)}\t{clean(author)}\t{','.join(map(str, cats))}\t{rank:g}")
    data = ("\n".join(lines) + "\n").encode("utf-8")
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)  # raw DEFLATE
    out = compressor.compress(data) + compressor.flush()
    dest = Path(__file__).resolve().parent.parent / "Lexi" / "Resources" / "gutenberg-catalog.bin"
    dest.write_bytes(out)
    print(f"{len(books)} books, {len(data) / 1e6:.1f} MB text, {len(out) / 1e6:.2f} MB compressed → {dest}")
    for i in POPULAR[:12]:
        if i in books:
            print(f"  {i:6} {books[i][0][:45]!r:48} {books[i][1]}")

if __name__ == "__main__":
    main(sys.argv[1])
