#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

RESULTS_PATH = "/home/user/results.json"
SCRIPT_PATH = "/home/user/analyze.py"
DB_PATH = "/home/user/citations.db"


def test_results_file_exists():
    assert os.path.exists(RESULTS_PATH), f"The expected output file {RESULTS_PATH} does not exist."
    assert os.path.isfile(RESULTS_PATH), f"{RESULTS_PATH} is not a file."


def test_results_content():
    with open(RESULTS_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS_PATH} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON output must be a list of objects."
    assert len(data) == 3, f"Expected exactly 3 authors in the results, got {len(data)}."

    expected_results = [
        {"author_name": "Bob", "score": 2.5, "rank": 1},
        {"author_name": "Alice", "score": 2.0, "rank": 2},
        {"author_name": "Charlie", "score": 1.0, "rank": 3}
    ]

    for i, expected in enumerate(expected_results):
        actual = data[i]
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."

        expected_keys = {"author_name", "score", "rank"}
        actual_keys = set(actual.keys())
        assert actual_keys == expected_keys, f"Item at index {i} has incorrect keys. Expected {expected_keys}, got {actual_keys}."

        assert actual["author_name"] == expected["author_name"], f"Expected author_name '{expected['author_name']}' at rank {expected['rank']}, got '{actual['author_name']}'."
        assert isinstance(actual["score"], (int, float)), f"Score for {actual['author_name']} must be a float."
        assert float(actual["score"]) == expected["score"], f"Expected score {expected['score']} for {actual['author_name']}, got {actual['score']}."
        assert actual["rank"] == expected["rank"], f"Expected rank {expected['rank']} for {actual['author_name']}, got {actual['rank']}."


def _make_unseen_database(path):
    rng = secrets.SystemRandom()
    author_count = 8
    paper_count = 24

    while True:
        token = secrets.token_hex(6)
        authors = [(1000 + i * 7, f"Researcher_{token}_{i}") for i in range(author_count)]
        author_ids = [row[0] for row in authors]

        assignments = author_ids[:]
        assignments.extend(rng.choice(author_ids) for _ in range(paper_count - author_count))
        rng.shuffle(assignments)
        paper_ids = [2000 + i * 11 for i in range(paper_count)]
        papers = [
            (paper_ids[i], f"Study_{token}_{i}", assignments[i], 1990 + (i % 35))
            for i in range(paper_count)
        ]

        citations = []
        for citing_index in range(1, paper_count):
            for cited_index in range(citing_index):
                if rng.random() < 0.16:
                    citations.append((paper_ids[citing_index], paper_ids[cited_index]))

        owner = {paper_id: author_id for paper_id, _, author_id, _ in papers}
        direct = {author_id: 0 for author_id in author_ids}
        indirect = {author_id: 0 for author_id in author_ids}
        incoming = {}

        for citing, cited in citations:
            direct[owner[cited]] += 1
            incoming.setdefault(cited, []).append(citing)

        for middle, target in citations:
            for source in incoming.get(middle, []):
                indirect[owner[target]] += 1

        scores = {
            author_id: float(direct[author_id]) + 0.5 * indirect[author_id]
            for author_id in author_ids
        }

        # Avoid ranking ambiguities in this behavioral test.
        if len(set(scores.values())) == author_count and max(scores.values()) > 0:
            break

    if os.path.exists(path):
        os.remove(path)
    conn = sqlite3.connect(path)
    try:
        conn.execute("CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT)")
        conn.execute("CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, author_id INTEGER, year INTEGER)")
        conn.execute("CREATE TABLE citations (citing_paper_id INTEGER, cited_paper_id INTEGER)")
        conn.executemany("INSERT INTO authors VALUES (?, ?)", authors)
        conn.executemany("INSERT INTO papers VALUES (?, ?, ?, ?)", papers)
        conn.executemany("INSERT INTO citations VALUES (?, ?)", citations)
        conn.commit()
    finally:
        conn.close()

    names = dict(authors)
    ordered = sorted(author_ids, key=lambda aid: (-scores[aid], names[aid]))
    return [
        {"author_name": names[aid], "score": scores[aid], "rank": rank}
        for rank, aid in enumerate(ordered[:3], 1)
    ]


def test_analysis_script_executes_and_computes_database_results():
    assert os.path.exists(SCRIPT_PATH), f"The required script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

    with tempfile.TemporaryDirectory() as tmpdir:
        db_backup = os.path.join(tmpdir, "citations.db")
        results_backup = os.path.join(tmpdir, "results.json")
        shutil.copy2(DB_PATH, db_backup)
        had_results = os.path.isfile(RESULTS_PATH)
        if had_results:
            shutil.copy2(RESULTS_PATH, results_backup)

        try:
            expected = _make_unseen_database(DB_PATH)
            if os.path.lexists(RESULTS_PATH):
                os.remove(RESULTS_PATH)

            completed = subprocess.run(
                ["python3", SCRIPT_PATH],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
            assert completed.returncode == 0, (
                f"{SCRIPT_PATH} failed when executed (exit {completed.returncode}). "
                f"stderr: {completed.stderr}"
            )
            assert os.path.isfile(RESULTS_PATH), "Running analyze.py did not create results.json."

            try:
                with open(RESULTS_PATH, "r") as f:
                    actual = json.load(f)
            except (OSError, json.JSONDecodeError) as exc:
                pytest.fail(f"The generated results.json is not valid JSON: {exc}")

            assert isinstance(actual, list), "The generated JSON output must be a list."
            assert len(actual) == 3, f"Expected exactly 3 generated results, got {len(actual)}."
            for i, expected_item in enumerate(expected):
                item = actual[i]
                assert isinstance(item, dict), f"Generated item {i} is not an object."
                assert set(item) == {"author_name", "score", "rank"}, f"Generated item {i} has incorrect keys."
                assert item["author_name"] == expected_item["author_name"], f"Incorrect author at generated rank {i + 1}."
                assert isinstance(item["score"], (int, float)) and not isinstance(item["score"], bool), f"Invalid score at generated rank {i + 1}."
                assert float(item["score"]) == expected_item["score"], f"Incorrect score at generated rank {i + 1}."
                assert item["rank"] == expected_item["rank"], f"Incorrect rank at generated position {i + 1}."
        finally:
            shutil.copy2(db_backup, DB_PATH)
            if had_results:
                shutil.copy2(results_backup, RESULTS_PATH)
            elif os.path.lexists(RESULTS_PATH):
                os.remove(RESULTS_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
