#!/usr/bin/env python3
"""Checks the Schakel word-link lists and reports how many chains they allow.

Usage: python3 Scripts/check_words.py [Resources]
Fails (exit 1) on malformed lines or duplicate links.
"""
import collections, re, sys, pathlib

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).parent.parent / "Resources")
ok = True
for path in sorted(root.glob("pairs_*.txt")):
    links, seen = [], set()
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        main, _, display = line.partition("=")
        words = main.split()
        if len(words) != 2 or not all(re.fullmatch(r"[a-z]{2,12}", w) for w in words) or words[0] == words[1]:
            print(f"{path.name}:{n}: malformed link: {raw!r}"); ok = False; continue
        if display.strip() and not re.fullmatch(r"[a-z]+", display.strip()):
            print(f"{path.name}:{n}: malformed written form: {raw!r}"); ok = False
        key = tuple(words)
        if key in seen:
            print(f"{path.name}:{n}: duplicate link: {raw!r}"); ok = False
        seen.add(key); links.append(key)

    out = collections.defaultdict(set)
    for a, b in links:
        out[a].add(b)
    words = {w for l in links for w in l}
    # Count walks of each length (an upper bound on distinct chains; repeats are rejected in the game).
    walks = {w: 1 for w in words}
    counts = []
    for length in range(2, 10):
        walks = {w: sum(walks.get(b, 0) for b in out[w]) for w in words}
        counts.append((length, sum(walks.values())))
    print(f"{path.name}: {len(links)} links, {len(words)} words")
    for length, c in counts:
        print(f"   chains of {length} words: ~{c:,}")
sys.exit(0 if ok else 1)
