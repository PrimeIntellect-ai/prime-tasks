#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess

SOURCE_PATH = "/home/user/workspace/analyze_graph.c"
EXEC_PATH = "/home/user/workspace/analyze_graph"
REBUILT_PATH = "/tmp/analyze_graph_rebuilt"
PAPERS_PATH = "/home/user/dataset/papers.json"
AUTHORS_PATH = "/home/user/dataset/authors.csv"
OUTPUT_PATH = "/home/user/results/top_authors.txt"

ORIGINAL_PAPERS = [
    {"paper_id": 1, "title": "Intro to Graphs", "year": 2020},
    {"paper_id": 2, "title": "Advanced Trees", "year": 2021},
    {"paper_id": 3, "title": "Centrality Metrics", "year": 2021},
    {"paper_id": 4, "title": "Clustering", "year": 2022},
    {"paper_id": 5, "title": "Network Dynamics", "year": 2023},
]
ORIGINAL_ROWS = [
    (1, "Alice"), (1, "Bob"), (1, "Charlie"),
    (2, "Bob"), (2, "David"),
    (3, "Alice"), (3, "Eve"),
    (4, "Charlie"), (4, "Eve"),
    (5, "Alice"), (5, "Bob"), (5, "Charlie"), (5, "Eve"),
]


def write_dataset(papers, rows):
    os.makedirs(os.path.dirname(PAPERS_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(PAPERS_PATH, "w", encoding="utf-8") as f:
        json.dump(papers, f, indent=2)
    with open(AUTHORS_PATH, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["paper_id", "author_name"])
        writer.writerows(rows)
    if os.path.exists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)


def derive_expected():
    with open(PAPERS_PATH, encoding="utf-8") as f:
        valid_papers = {str(item["paper_id"]) for item in json.load(f)}

    by_paper = {paper_id: set() for paper_id in valid_papers}
    with open(AUTHORS_PATH, encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            paper_id = row["paper_id"]
            if paper_id in by_paper:
                by_paper[paper_id].add(row["author_name"])

    graph = {}
    for authors in by_paper.values():
        for author in authors:
            graph.setdefault(author, set())
        for author in authors:
            graph[author].update(authors - {author})

    ranked = sorted(graph.items(), key=lambda item: (-len(item[1]), item[0]))[:3]
    return [f"{author}:{len(neighbors)}" for author, neighbors in ranked]


def run_and_read(executable):
    if os.path.exists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    result = subprocess.run(
        [executable],
        cwd="/home/user/workspace",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing after running {executable}."
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def assert_case(executable, papers, rows):
    write_dataset(papers, rows)
    expected = derive_expected()
    assert len(expected) == 3
    actual = run_and_read(executable)
    assert actual == expected, f"For {executable}, expected {expected}, got {actual}."


def test_c_source_and_executable_exist():
    source_path = "/home/user/workspace/analyze_graph.c"
    exec_path = "/home/user/workspace/analyze_graph"

    assert os.path.isfile(source_path), f"C source file {source_path} is missing."
    assert os.path.isfile(exec_path), f"Executable file {exec_path} is missing."
    assert os.access(exec_path, os.X_OK), f"File {exec_path} is not executable."

    with open(exec_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {exec_path} is not a compiled executable."

    result = subprocess.run(
        ["gcc", "-O2", SOURCE_PATH, "-o", REBUILT_PATH, "-ljson-c", "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"C source failed to compile: {result.stderr}"
    assert os.path.isfile(REBUILT_PATH) and os.access(REBUILT_PATH, os.X_OK)


def test_top_authors_output():
    # Run the submitted executable on the supplied dataset before retaining the
    # original verifier's exact output assertions.
    write_dataset(ORIGINAL_PAPERS, ORIGINAL_ROWS)
    run_and_read(EXEC_PATH)

    output_path = "/home/user/results/top_authors.txt"

    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Bob:4",
        "Alice:3",
        "Charlie:3"
    ]

    assert len(lines) == 3, f"Expected exactly 3 lines in {output_path}, found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."

    # The independently rebuilt C source must produce the same supplied-data result.
    assert_case(REBUILT_PATH, ORIGINAL_PAPERS, ORIGINAL_ROWS)

    token = secrets.token_hex(6)
    dynamic_papers_1 = [
        {"paper_id": 101, "title": "One", "year": 2018},
        {"paper_id": 205, "title": "Two", "year": 2019},
        {"paper_id": 309, "title": "Three", "year": 2020},
        {"paper_id": 411, "title": "Four", "year": 2021},
        {"paper_id": 512, "title": "Solo", "year": 2022},
    ]
    dynamic_rows_1 = [
        (101, f"Zed_{token}"), (101, f"Amy_{token}"), (101, f"Moe_{token}"),
        (205, f"Amy_{token}"), (205, f"Kai_{token}"),
        (309, f"Moe_{token}"), (309, f"Kai_{token}"), (309, f"Nia_{token}"),
        (411, f"Zed_{token}"), (411, f"Nia_{token}"),
        (512, f"Solo_{token}"),
        (999, f"Ignored_{token}"),
    ]

    dynamic_papers_2 = [
        {"paper_id": 7, "title": "Repeat A", "year": 2023},
        {"paper_id": 8, "title": "Repeat B", "year": 2024},
        {"paper_id": 9, "title": "Group", "year": 2025},
        {"paper_id": 10, "title": "Pair", "year": 2026},
    ]
    dynamic_rows_2 = [
        (7, f"A_{token}"), (7, f"B_{token}"), (7, f"B_{token}"),
        (8, f"A_{token}"), (8, f"B_{token}"),
        (9, f"B_{token}"), (9, f"C_{token}"), (9, f"D_{token}"),
        (10, f"D_{token}"), (10, f"E_{token}"),
    ]

    for executable in (EXEC_PATH, REBUILT_PATH):
        assert_case(executable, dynamic_papers_1, dynamic_rows_1)
        assert_case(executable, dynamic_papers_2, dynamic_rows_2)

    # Leave the requested supplied-data result in its final location.
    write_dataset(ORIGINAL_PAPERS, ORIGINAL_ROWS)
    final_lines = run_and_read(EXEC_PATH)
    assert final_lines == expected_lines
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
