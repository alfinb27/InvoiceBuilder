#!/usr/bin/env python3
"""Compiles every Room @Query of the Android app on SQLite 3.18.0, the version Android 8.0 ships (minSdk 26).

Builds the SQLite shell from the official amalgamation once (into android/build/sqlite-floor), creates a database
from the spec migrations with it, then runs `EXPLAIN <query>` for each query: SQL that an old phone cannot parse,
or a function it does not have (json_extract), fails here as it would on the phone. `SQLiteFloorTests` is the quick
always-on version of this check. Run it with `make check-android-sql`.
"""
import pathlib
import re
import subprocess
import sys
import urllib.request
import zipfile

VERSION, URL = "3180000", "https://www.sqlite.org/2017/sqlite-amalgamation-3180000.zip"
ROOT = pathlib.Path(__file__).resolve().parents[2]
WORK = ROOT / "android/build/sqlite-floor"


def shell() -> pathlib.Path:
    binary = WORK / f"sqlite3-{VERSION}"
    if binary.exists():
        return binary
    WORK.mkdir(parents=True, exist_ok=True)
    archive = WORK / "amalgamation.zip"
    urllib.request.urlretrieve(URL, archive)
    with zipfile.ZipFile(archive) as zipped:
        zipped.extractall(WORK)
    source = WORK / f"sqlite-amalgamation-{VERSION}"
    subprocess.run(["cc", "-O1", "-w", "-DSQLITE_THREADSAFE=0", "-DSQLITE_OMIT_LOAD_EXTENSION",
                    str(source / "shell.c"), str(source / "sqlite3.c"), "-o", str(binary)], check=True)
    return binary


def main() -> int:
    sqlite = shell()
    database = WORK / "floor.db"
    database.unlink(missing_ok=True)
    for migration in sorted((ROOT / "spec/schema/db/migrations").glob("*.sql")):
        result = subprocess.run([str(sqlite), "-bail", str(database)], stdin=migration.open(), capture_output=True, text=True)
        if result.returncode != 0:
            print(f"{migration.relative_to(ROOT)}: {result.stderr.strip()}")
            return 1

    query = re.compile(r'@Query\(\s*(?:"""(.*?)"""|"((?:[^"\\]|\\.)*)")', re.S)
    count, failures = 0, 0
    for source in sorted((ROOT / "android").rglob("*.kt")):
        if "/build/" in source.as_posix():
            continue
        text = source.read_text()
        for match in query.finditer(text):
            sql = (match.group(1) or match.group(2)).strip()
            count += 1
            result = subprocess.run([str(sqlite), str(database), f"EXPLAIN {sql};"], capture_output=True, text=True)
            if result.returncode != 0 or result.stderr:
                failures += 1
                line = text[: match.start()].count("\n") + 1
                print(f"{source.relative_to(ROOT)}:{line}: {result.stderr.strip()}\n    {' '.join(sql.split())[:160]}")
    print(f"SQLite {VERSION}: {count} queries compiled, {failures} failed")
    return 1 if failures or count == 0 else 0


if __name__ == "__main__":
    sys.exit(main())
