#!/usr/bin/env python3
"""Construit un index compact a partir de anime-offline-database.

Le jeu de donnees d'origine agrege MyAnimeList, AniDB, AniList et Kitsu.
Il pese une centaine de megaoctets : on n'en garde que ce dont l'application
a besoin pour reconnaitre un dossier, puis on compresse.

Licence des donnees : ODbL et CC BY-SA, manami-project.
Notre fichier derive reste sous les memes conditions.
"""

import gzip
import io
import json
import os
import sys
import urllib.request
import zipfile
from datetime import datetime, timezone

SOURCE_REPO = "manami-project/anime-offline-database"
OUTPUT_DIR = "data"
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "anime-index.json.gz")
META_FILE = os.path.join(OUTPUT_DIR, "anime-index-meta.json")

MAX_SYNONYMS = 10
MAX_TAGS = 6
UA = {"User-Agent": "AnimeOrganizer-IndexBuilder/1.0"}


def fetch(url, timeout=180):
    request = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def find_dataset_url():
    """Le jeu de donnees est publie en release, plus dans le depot."""
    api = f"https://api.github.com/repos/{SOURCE_REPO}/releases/latest"
    release = json.loads(fetch(api).decode("utf-8"))

    candidates = []
    for asset in release.get("assets", []):
        name = asset.get("name", "")
        if "anime-offline-database" not in name:
            continue
        if "dead-entries" in name:
            continue
        candidates.append((name, asset.get("browser_download_url")))

    if not candidates:
        raise RuntimeError("Aucun fichier de donnees dans la derniere release.")

    # On prefere la version minifiee, puis le zip, plus legers a telecharger.
    def rank(item):
        name = item[0]
        score = 0
        if "minified" in name:
            score -= 2
        if name.endswith(".zip"):
            score -= 1
        return score

    candidates.sort(key=rank)
    print("Fichiers disponibles :", [c[0] for c in candidates])
    print("Choisi :", candidates[0][0])
    return candidates[0]


def load_dataset(name, url):
    raw = fetch(url)
    print(f"Telecharge : {len(raw) / 1_000_000:.1f} Mo")

    if name.endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            inner = [n for n in archive.namelist() if n.endswith(".json")]
            if not inner:
                raise RuntimeError("Archive sans fichier JSON.")
            raw = archive.read(inner[0])
    elif name.endswith(".gz"):
        raw = gzip.decompress(raw)

    return json.loads(raw.decode("utf-8"))


def extract_ids(sources):
    """Recupere les identifiants des bases connues depuis les URL sources."""
    ids = {}
    for url in sources or []:
        if "anilist.co/anime/" in url:
            ids["a"] = url.rstrip("/").split("/")[-1]
        elif "myanimelist.net/anime/" in url:
            ids["m"] = url.rstrip("/").split("/")[-1]
        elif "kitsu." in url:
            ids["k"] = url.rstrip("/").split("/")[-1]
    return {k: int(v) for k, v in ids.items() if v.isdigit()}


def compact(entry):
    title = (entry.get("title") or "").strip()
    if not title:
        return None

    season = entry.get("animeSeason") or {}
    year = season.get("year")
    episodes = entry.get("episodes") or 0

    synonyms = [s.strip() for s in entry.get("synonyms") or [] if s and s.strip()]
    # Les doublons de casse n'apportent rien une fois la comparaison normalisee.
    seen = set()
    unique = []
    for s in synonyms:
        key = s.lower()
        if key in seen or key == title.lower():
            continue
        seen.add(key)
        unique.append(s)
        if len(unique) >= MAX_SYNONYMS:
            break

    item = {
        "t": title,
        "s": unique,
        "f": entry.get("type") or "UNKNOWN",
        "e": episodes if episodes > 0 else None,
        "y": year,
        "p": entry.get("picture") or entry.get("thumbnail"),
        "g": (entry.get("tags") or [])[:MAX_TAGS],
    }
    item.update(extract_ids(entry.get("sources")))
    return {k: v for k, v in item.items() if v not in (None, [], "")}


def main():
    name, url = find_dataset_url()
    dataset = load_dataset(name, url)

    entries = dataset.get("data") or dataset.get("anime") or []
    print("Entrees dans la source :", len(entries))

    index = []
    for entry in entries:
        item = compact(entry)
        if item:
            index.append(item)

    payload = {
        "version": 1,
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "source": SOURCE_REPO,
        "license": "ODbL 1.0 / CC BY-SA 4.0 - manami-project",
        "count": len(index),
        "anime": index,
    }

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    with gzip.open(OUTPUT_FILE, "wb", compresslevel=9) as f:
        f.write(body)

    with open(META_FILE, "w", encoding="utf-8") as f:
        json.dump(
            {
                "generated": payload["generated"],
                "count": payload["count"],
                "source": SOURCE_REPO,
                "license": payload["license"],
                "bytes": os.path.getsize(OUTPUT_FILE),
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

    print(f"Index : {len(index)} entrees")
    print(f"JSON brut : {len(body) / 1_000_000:.1f} Mo")
    print(f"Compresse : {os.path.getsize(OUTPUT_FILE) / 1_000_000:.1f} Mo")
    return 0


if __name__ == "__main__":
    sys.exit(main())
