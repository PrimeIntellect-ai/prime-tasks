#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import itertools
import json
import os
import py_compile
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

HOME = "/home/user"
SCRIPT = os.path.join(HOME, "process_network.py")
CSV_PATH = os.path.join(HOME, "cross_country_collaborations.csv")
AUTHORS_DB = os.path.join(HOME, "authors.db")
INSTITUTIONS_DB = os.path.join(HOME, "institutions.db")
PAPERS = os.path.join(HOME, "papers.jsonl")
HEADERS = ["author1_name", "author2_name", "author1_country", "author2_country", "paper_count"]


def run_submission():
    assert os.path.isfile(SCRIPT), f"Required script {SCRIPT} does not exist."
    assert os.path.getsize(SCRIPT) > 0, f"Required script {SCRIPT} is empty."
    py_compile.compile(SCRIPT, doraise=True)
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    subprocess.run(["python3", SCRIPT], cwd=HOME, check=True, timeout=20)
    assert os.path.isfile(CSV_PATH), f"File {CSV_PATH} does not exist. The script might not have been executed or saved it to the wrong path."


def read_csv():
    with open(CSV_PATH, "r", encoding="utf-8", newline="") as f:
        return list(csv.reader(f))


def assert_original_expected_rows():
    rows = read_csv()
    assert len(rows) > 0, "The generated CSV file is empty."

    headers = rows[0]
    expected_headers = HEADERS
    assert headers == expected_headers, f"CSV headers are incorrect. Expected {expected_headers}, got {headers}."

    data_rows = rows[1:]
    expected_rows = [
        ["Alice Adams", "Bob Brown", "USA", "UK", "2"],
        ["Alice Adams", "David Davis", "USA", "Switzerland", "1"],
        ["Bob Brown", "Charlie Clark", "UK", "USA", "1"],
        ["Bob Brown", "David Davis", "UK", "Switzerland", "1"],
        ["Bob Brown", "Frank Ford", "UK", "USA", "1"],
        ["David Davis", "Eve Evans", "Switzerland", "UK", "1"]
    ]

    assert len(data_rows) == len(expected_rows), f"Expected {len(expected_rows)} data rows, got {len(data_rows)}. Ensure you are filtering cross-country collaborations correctly."
    for i, (actual, expected) in enumerate(zip(data_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}. Check your sorting, alphabetical ordering of author pairs, and paper counts."


def derive_expected_from_inputs():
    with sqlite3.connect(AUTHORS_DB) as db:
        authors = {row[0]: (row[1], row[2]) for row in db.execute("SELECT id, name, institution_id FROM authors")}
    with sqlite3.connect(INSTITUTIONS_DB) as db:
        countries = {row[0]: row[1] for row in db.execute("SELECT id, country FROM institutions")}

    counts = {}
    with open(PAPERS, "r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            paper = json.loads(line)
            ids = list(dict.fromkeys(paper["author_ids"]))
            for left_id, right_id in itertools.combinations(ids, 2):
                if left_id not in authors or right_id not in authors:
                    continue
                left_name, left_inst = authors[left_id]
                right_name, right_inst = authors[right_id]
                left_country = countries[left_inst]
                right_country = countries[right_inst]
                if left_country == right_country:
                    continue
                if left_name < right_name:
                    key = (left_name, right_name, left_country, right_country)
                else:
                    key = (right_name, left_name, right_country, left_country)
                counts[key] = counts.get(key, 0) + 1

    data = [[a1, a2, c1, c2, str(count)] for (a1, a2, c1, c2), count in counts.items()]
    data.sort(key=lambda row: (-int(row[4]), row[0], row[1]))
    return [HEADERS] + data


def test_script_executes_and_processes_inputs():
    run_submission()
    assert_original_expected_rows()

    with tempfile.TemporaryDirectory() as backup:
        for path in (AUTHORS_DB, INSTITUTIONS_DB, PAPERS):
            shutil.copy2(path, os.path.join(backup, os.path.basename(path)))

        try:
            token = uuid.uuid4().hex
            with sqlite3.connect(AUTHORS_DB) as db:
                next_author = db.execute("SELECT COALESCE(MAX(id), 0) + 1000 FROM authors").fetchone()[0]
            with sqlite3.connect(INSTITUTIONS_DB) as db:
                next_inst = db.execute("SELECT COALESCE(MAX(id), 0) + 1000 FROM institutions").fetchone()[0]
                db.executemany(
                    "INSERT INTO institutions(id, name, country) VALUES (?, ?, ?)",
                    [
                        (next_inst, "Probe Institution A " + token, "ProbeCountryA-" + token),
                        (next_inst + 1, "Probe Institution B " + token, "ProbeCountryB-" + token),
                    ],
                )
            with sqlite3.connect(AUTHORS_DB) as db:
                db.executemany(
                    "INSERT INTO authors(id, name, institution_id) VALUES (?, ?, ?)",
                    [
                        (next_author, "Probe Alpha " + token, next_inst),
                        (next_author + 1, "Probe Omega " + token, next_inst + 1),
                    ],
                )
            with open(PAPERS, "a", encoding="utf-8") as f:
                for suffix in ("one", "two"):
                    f.write(json.dumps({
                        "paper_id": "probe-" + token + "-" + suffix,
                        "title": "Verifier probe",
                        "author_ids": [next_author, next_author + 1],
                    }) + "\n")

            expected = derive_expected_from_inputs()
            run_submission()
            actual = read_csv()
            assert actual == expected, "The script did not recompute the collaboration CSV from the modified SQLite and JSONL inputs."
        finally:
            for path in (AUTHORS_DB, INSTITUTIONS_DB, PAPERS):
                shutil.copy2(os.path.join(backup, os.path.basename(path)), path)
            run_submission()

    assert_original_expected_rows()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
