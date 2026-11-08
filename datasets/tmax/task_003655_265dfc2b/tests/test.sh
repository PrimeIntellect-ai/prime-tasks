#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import secrets
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict

HOME = "/home/user"
SCRIPT = os.path.join(HOME, "process_data.py")
AUTHORS = os.path.join(HOME, "authors.csv")
PAPERS = os.path.join(HOME, "papers.jsonl")
CITATIONS = os.path.join(HOME, "citations.txt")
OUTPUT = os.path.join(HOME, "top_authors.txt")


def compute_expected():
    authors = {}
    with open(AUTHORS, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            authors[int(row["author_id"])] = row["name"]

    papers = {}
    with open(PAPERS, "r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            data = json.loads(line)
            papers[data["id"]] = {
                "year": data["year"],
                "authors": data["authors"],
            }

    author_counts = defaultdict(int)
    with open(CITATIONS, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            citing_id, cited_id = line.split()
            if citing_id in papers and cited_id in papers:
                citing_year = papers[citing_id]["year"]
                cited_year = papers[cited_id]["year"]
                if cited_year < 2020 and citing_year >= 2022:
                    for author_id in papers[cited_id]["authors"]:
                        author_counts[author_id] += 1

    expected_results = []
    for author_id, count in author_counts.items():
        if count > 0:
            expected_results.append((authors[author_id], count))
    expected_results.sort(key=lambda x: (-x[1], x[0]))
    return [f"{name}:{count}" for name, count in expected_results]


def execute_and_check(expected_lines):
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"process_data.py exited with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} is missing."
    assert os.path.isfile(OUTPUT), f"Output path {OUTPUT} is not a regular file."

    with open(OUTPUT, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {OUTPUT} do not match the expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )


def write_runtime_fixture():
    token = secrets.token_hex(8)
    names = [
        f"Zeta Researcher {token}",
        f"Alpha Researcher {token}",
        f"Middle Researcher {token}",
        f"No Citations {token}",
    ]
    with open(AUTHORS, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["author_id", "name"])
        writer.writerows([(101, names[0]), (207, names[1]), (333, names[2]), (490, names[3])])

    ids = {key: f"{key}_{token}" for key in ["old_a", "old_b", "boundary", "new_a", "new_b", "new_c", "too_early"]}
    papers = [
        {"id": ids["old_a"], "year": 2019, "authors": [101, 207]},
        {"id": ids["old_b"], "year": 2017, "authors": [333]},
        {"id": ids["boundary"], "year": 2020, "authors": [490]},
        {"id": ids["new_a"], "year": 2022, "authors": [490]},
        {"id": ids["new_b"], "year": 2025, "authors": [101]},
        {"id": ids["new_c"], "year": 2024, "authors": [207]},
        {"id": ids["too_early"], "year": 2021, "authors": [333]},
    ]
    with open(PAPERS, "w", encoding="utf-8") as f:
        for paper in papers:
            f.write(json.dumps(paper) + "\n")

    edges = [
        (ids["new_a"], ids["old_a"]),
        (ids["new_b"], ids["old_a"]),
        (ids["new_a"], ids["old_b"]),
        (ids["new_b"], ids["old_b"]),
        (ids["new_c"], ids["old_b"]),
        (ids["new_a"], ids["boundary"]),
        (ids["too_early"], ids["old_a"]),
    ]
    with open(CITATIONS, "w", encoding="utf-8") as f:
        for citing, cited in edges:
            f.write(f"{citing} {cited}\n")


def test_top_authors_output():
    assert os.path.exists(SCRIPT), f"Required script {SCRIPT} is missing."
    assert os.path.isfile(SCRIPT), f"Required script {SCRIPT} is not a regular file."

    with tempfile.TemporaryDirectory() as backup:
        paths = [AUTHORS, PAPERS, CITATIONS, OUTPUT]
        present = {}
        for path in paths:
            present[path] = os.path.exists(path)
            if present[path]:
                shutil.copy2(path, os.path.join(backup, os.path.basename(path)))

        try:
            # Preserve the original verifier's exact behavioral assertion, but
            # require the submitted script to freshly generate the output.
            original_expected = compute_expected()
            execute_and_check(original_expected)

            # Exercise the script on unpredictable data to reject fixed-output
            # and fixture-hardcoded submissions.
            write_runtime_fixture()
            runtime_expected = compute_expected()
            execute_and_check(runtime_expected)
        finally:
            for path in paths:
                if os.path.lexists(path):
                    os.remove(path)
                if present[path]:
                    shutil.copy2(os.path.join(backup, os.path.basename(path)), path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
