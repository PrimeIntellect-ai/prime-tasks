#!/bin/bash
set -e
mkdir -p /logs/verifier

backup_db=$(mktemp /tmp/research.db.backup.XXXXXX)
cp /home/user/research.db "$backup_db"
export VERIFIER_DB_BACKUP="$backup_db"
trap 'cp "$VERIFIER_DB_BACKUP" /home/user/research.db; rm -f "$VERIFIER_DB_BACKUP"' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import sqlite3
import subprocess
from collections import deque

DB_PATH = "/home/user/research.db"
OUTPUT_JSON_PATH = "/home/user/path_results.json"
CARGO_PROJECT_PATH = "/home/user/citation_processor"
BACKUP_PATH = os.environ["VERIFIER_DB_BACKUP"]

EXPECTED_PAPERS = [
    (1, "Origin Paper", 2020, 10.5),
    (2, "Second Paper", 2020, 12.0),
    (3, "Third Paper", 2021, 8.0),
    (4, "Shortcut Paper", 2021, 9.5),
    (5, "Target Paper", 2022, 15.0),
    (6, "Noise Paper", 2020, 15.0),
]
EXPECTED_CITATIONS = [(1, 2), (1, 4), (2, 3), (3, 5), (4, 5)]
EXPECTED_OUTPUT = [
    {"id": 1, "title": "Origin Paper", "year": 2020, "score": 10.5, "year_rank": 3},
    {"id": 4, "title": "Shortcut Paper", "year": 2021, "score": 9.5, "year_rank": 1},
    {"id": 5, "title": "Target Paper", "year": 2022, "score": 15.0, "year_rank": 1},
]


def read_database():
    conn = sqlite3.connect(DB_PATH)
    try:
        papers = conn.execute(
            "SELECT id, title, year, score FROM papers ORDER BY id"
        ).fetchall()
        citations = conn.execute(
            "SELECT source_id, target_id FROM citations ORDER BY source_id, target_id"
        ).fetchall()
        return papers, citations
    finally:
        conn.close()


def run_submission():
    if os.path.exists(OUTPUT_JSON_PATH):
        os.remove(OUTPUT_JSON_PATH)
    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=CARGO_PROJECT_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"cargo run failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_JSON_PATH), (
        f"Running the Rust program did not create {OUTPUT_JSON_PATH}"
    )
    try:
        with open(OUTPUT_JSON_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{OUTPUT_JSON_PATH} does not contain valid JSON: {exc}")


def assert_output_types(data):
    assert isinstance(data, list), "Output JSON must be an array"
    required = {"id", "title", "year", "score", "year_rank"}
    for row in data:
        assert isinstance(row, dict), "Each output element must be an object"
        assert set(row) == required, f"Incorrect output keys: {set(row)}"
        assert type(row["id"]) is int
        assert type(row["title"]) is str
        assert type(row["year"]) is int
        assert type(row["score"]) is float
        assert type(row["year_rank"]) is int


def expected_from_rows(papers, citations):
    by_id = {row[0]: row for row in papers}
    adjacency = {}
    for source, target in citations:
        adjacency.setdefault(source, []).append(target)

    queue = deque([[1]])
    visited = {1}
    path = None
    while queue:
        candidate = queue.popleft()
        current = candidate[-1]
        if current == 5:
            path = candidate
            break
        for target in adjacency.get(current, []):
            if target not in visited:
                visited.add(target)
                queue.append(candidate + [target])
    assert path is not None, "Verifier-generated database unexpectedly has no path"

    ranks = {}
    years = {row[2] for row in papers}
    for year in years:
        distinct_scores = sorted(
            {row[3] for row in papers if row[2] == year}, reverse=True
        )
        for paper_id, _, paper_year, score in papers:
            if paper_year == year:
                ranks[paper_id] = distinct_scores.index(score) + 1

    result = []
    for paper_id in path:
        pid, title, year, score = by_id[paper_id]
        result.append({
            "id": pid,
            "title": title,
            "year": year,
            "score": score,
            "year_rank": ranks[pid],
        })
    return result


def install_dynamic_database():
    rng = random.Random(secrets.randbits(128))
    token = secrets.token_hex(8)
    ids = list(range(1, 10))
    years = [2010 + rng.randrange(0, 4) for _ in ids]
    scores = [float(rng.randrange(20, 300)) + 0.25 for _ in ids]
    # Force a tie so DENSE_RANK behavior is exercised.
    years[1] = years[2]
    scores[1] = scores[2]
    papers = [
        (paper_id, f"Dynamic {token} paper {paper_id}", years[paper_id - 1], scores[paper_id - 1])
        for paper_id in ids
    ]

    middle = rng.sample([2, 3, 4, 6, 7, 8, 9], 5)
    a, b, c, d, e = middle
    # A unique shortest path of length three and a longer distractor path.
    citations = [(1, a), (a, b), (b, 5), (1, c), (c, d), (d, e), (e, 5)]
    rng.shuffle(citations)

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executescript("""
            CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER, score REAL);
            CREATE TABLE citations (source_id INTEGER, target_id INTEGER);
        """)
        conn.executemany(
            "INSERT INTO papers (id, title, year, score) VALUES (?, ?, ?, ?)", papers
        )
        conn.executemany(
            "INSERT INTO citations (source_id, target_id) VALUES (?, ?)", citations
        )
        conn.commit()
    finally:
        conn.close()
    return read_database()


def test_complete_submission():
    assert os.path.isdir(CARGO_PROJECT_PATH), (
        f"Cargo project directory not found at {CARGO_PROJECT_PATH}"
    )
    assert os.path.isfile(os.path.join(CARGO_PROJECT_PATH, "Cargo.toml")), (
        f"Cargo.toml not found in {CARGO_PROJECT_PATH}"
    )
    assert os.path.isfile(os.path.join(CARGO_PROJECT_PATH, "src", "main.rs")), (
        "Rust binary source src/main.rs was not found"
    )

    try:
        # Preserve the original verifier's database assertions.
        assert read_database() == (EXPECTED_PAPERS, EXPECTED_CITATIONS), (
            "The original database was modified before verification"
        )

        # Actually build and execute the submitted Rust project on the original DB.
        original_data = run_submission()
        assert_output_types(original_data)
        assert original_data == EXPECTED_OUTPUT, (
            f"JSON output does not match expected. Got: {original_data}"
        )
        assert read_database() == (EXPECTED_PAPERS, EXPECTED_CITATIONS), (
            "The Rust program modified the original database"
        )

        # Execute it again on unpredictable data and derive the answer independently.
        dynamic_before = install_dynamic_database()
        dynamic_expected = expected_from_rows(*dynamic_before)
        dynamic_data = run_submission()
        assert_output_types(dynamic_data)
        assert dynamic_data == dynamic_expected, (
            f"Program failed on verifier-generated database. Got: {dynamic_data}; "
            f"expected: {dynamic_expected}"
        )
        assert read_database() == dynamic_before, (
            "The Rust program modified the verifier-generated database"
        )

        # Restore the required final database and regenerate the required final output.
        shutil.copy2(BACKUP_PATH, DB_PATH)
        final_data = run_submission()
        assert_output_types(final_data)
        assert final_data == EXPECTED_OUTPUT
        assert read_database() == (EXPECTED_PAPERS, EXPECTED_CITATIONS)
    finally:
        shutil.copy2(BACKUP_PATH, DB_PATH)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
