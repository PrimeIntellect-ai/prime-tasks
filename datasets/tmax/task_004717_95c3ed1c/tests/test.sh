#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
from pathlib import Path

import pytest

ANALYZER = Path("/home/user/analyzer")
METADATA = Path("/home/user/data/metadata.csv")
CITATIONS = Path("/home/user/data/citations.txt")
REPORT = Path("/home/user/output/cycles_report.json")


def run_analyzer():
    if REPORT.exists():
        REPORT.unlink()

    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", str(ANALYZER / "Cargo.toml")],
        cwd=str(ANALYZER),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"Rust program failed to run:\n{result.stdout}"
    assert REPORT.is_file(), f"Expected output file is missing after running the program: {REPORT}"


def load_report():
    with REPORT.open("r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT} does not contain valid JSON.")


def derive_expected():
    scores = {}
    with METADATA.open(newline="") as f:
        for row in csv.DictReader(f):
            scores[row["paper_id"]] = int(row["impact_score"])

    adjacency = {}
    with CITATIONS.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            source, target = line.split(",")
            adjacency.setdefault(source, []).append(target)
            adjacency.setdefault(target, [])

    cycles = set()

    def search(start, node, path, visited):
        for nxt in adjacency.get(node, []):
            if nxt == start and len(path) >= 2:
                cycles.add(frozenset(path))
            elif nxt not in visited:
                search(start, nxt, path + [nxt], visited | {nxt})

    for start in adjacency:
        search(start, start, [start], {start})

    result = []
    for members in cycles:
        ordered = sorted(members)
        result.append({
            "cycle": ordered,
            "max_score": max(scores[paper] for paper in ordered),
        })
    result.sort(key=lambda item: (-item["max_score"], item["cycle"][0]))
    return result


def assert_report(actual_data, expected_data):
    assert isinstance(actual_data, list), "Output JSON should be a list of objects."
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} cycles, found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert "cycle" in actual, f"Object at index {i} missing 'cycle' key."
        assert "max_score" in actual, f"Object at index {i} missing 'max_score' key."
        assert actual["cycle"] == sorted(actual["cycle"]), f"Cycle at index {i} is not sorted lexicographically."
        assert actual["cycle"] == expected["cycle"], f"Cycle at index {i} mismatch. Expected {expected['cycle']}, got {actual['cycle']}."
        assert actual["max_score"] == expected["max_score"], f"max_score at index {i} mismatch. Expected {expected['max_score']}, got {actual['max_score']}."


def test_rust_project_runs_and_computes_reports():
    assert ANALYZER.is_dir(), f"Expected Rust project directory is missing: {ANALYZER}"
    assert (ANALYZER / "Cargo.toml").is_file(), "Rust project is missing Cargo.toml."
    assert (ANALYZER / "src").is_dir(), "Rust project is missing its src directory."
    assert any((ANALYZER / "src").rglob("*.rs")), "Rust project contains no Rust source files."

    build = subprocess.run(
        ["cargo", "build", "--quiet", "--manifest-path", str(ANALYZER / "Cargo.toml")],
        cwd=str(ANALYZER),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert build.returncode == 0, f"Rust project failed to build:\n{build.stdout}"

    # Exercise the program on the original dataset and retain the original verifier assertions.
    METADATA.write_text(
        "paper_id,year,impact_score\n"
        "P01,2020,45\nP02,2020,62\nP03,2021,55\n"
        "P04,2021,80\nP05,2022,91\nP06,2022,88\n"
        "P07,2019,30\nP08,2019,40\nP09,2020,75\n"
    )
    CITATIONS.write_text(
        "P01,P02\nP02,P03\nP03,P01\n"
        "P04,P05\nP05,P06\nP06,P04\n"
        "P01,P04\nP07,P08\nP08,P07\nP09,P04\n"
    )
    run_analyzer()
    actual_data = load_report()
    expected_data = [
        {"cycle": ["P04", "P05", "P06"], "max_score": 91},
        {"cycle": ["P01", "P02", "P03"], "max_score": 62},
        {"cycle": ["P07", "P08"], "max_score": 40},
    ]
    assert_report(actual_data, expected_data)

    # Replace both inputs with an unpredictable valid dataset, rerun, and derive
    # the expected answer independently from those generated files.
    token = secrets.token_hex(4).upper()
    ids = [f"T{token}_{i:02d}" for i in range(13)]
    cycle_groups = [ids[0:2], ids[2:5], ids[5:9]]
    scores = {paper: 100 + secrets.randbelow(900) for paper in ids}

    metadata_rows = [(paper, 2010 + secrets.randbelow(16), scores[paper]) for paper in ids]
    secrets.SystemRandom().shuffle(metadata_rows)
    with METADATA.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["paper_id", "year", "impact_score"])
        writer.writerows(metadata_rows)

    edges = []
    for group in cycle_groups:
        edges.extend((group[i], group[(i + 1) % len(group)]) for i in range(len(group)))
    edges.extend([
        (cycle_groups[0][0], cycle_groups[1][0]),
        (cycle_groups[1][1], cycle_groups[2][0]),
        (ids[9], ids[10]),
        (ids[10], ids[11]),
        (ids[11], cycle_groups[2][1]),
        (ids[12], ids[9]),
    ])
    secrets.SystemRandom().shuffle(edges)
    with CITATIONS.open("w") as f:
        for source, target in edges:
            f.write(f"{source},{target}\n")

    expected_dynamic = derive_expected()
    run_analyzer()
    assert_report(load_report(), expected_dynamic)
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
