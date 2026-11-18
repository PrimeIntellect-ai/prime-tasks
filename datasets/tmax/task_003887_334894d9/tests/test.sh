#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
from collections import defaultdict

import pytest

SOURCE_PATH = "/home/user/process_citations.c"
EXECUTABLE_PATH = "/home/user/process_citations"
CSV_PATH = "/home/user/citations.csv"
RESULTS_PATH = "/home/user/results.txt"

ORIGINAL_DATA = """101,102,2020
102,103,2020
103,104,2021
104,105,2021
108,103,2020
109,103,2020
110,105,2021
111,105,2022
112,111,2022
113,111,2022
114,101,2019
"""


def expected_report(csv_text):
    graph = defaultdict(list)
    nodes = set()
    yearly_counts = defaultdict(lambda: defaultdict(int))

    for line in csv_text.splitlines():
        if not line.strip():
            continue
        citing, cited, year = map(int, line.split(","))
        graph[citing].append(cited)
        nodes.add(citing)
        nodes.add(cited)
        yearly_counts[year][cited] += 1

    memo = {}

    def depth(node):
        if node not in memo:
            memo[node] = max((1 + depth(child) for child in graph[node]), default=0)
        return memo[node]

    longest = max((depth(node) for node in nodes), default=0)
    lines = [f"Longest Chain Length: {longest}"]
    for year in sorted(yearly_counts):
        counts = yearly_counts[year]
        best_count = max(counts.values())
        best_paper = min(paper for paper, count in counts.items() if count == best_count)
        lines.append(f"Top Paper {year}: {best_paper} ({best_count} citations)")
    return "\n".join(lines)


def run_case(csv_text):
    with open(CSV_PATH, "w") as f:
        f.write(csv_text)
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    completed = subprocess.run(
        [EXECUTABLE_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"process_citations exited with {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULTS_PATH), "Executable did not create /home/user/results.txt"
    with open(RESULTS_PATH, "r") as f:
        actual = f.read().strip()
    expected = expected_report(csv_text)
    assert actual == expected, f"Expected:\n{expected}\nActual:\n{actual}"


def test_c_source_file_exists():
    assert os.path.isfile(SOURCE_PATH), f"C source file not found at {SOURCE_PATH}"


def test_executable_exists_and_is_executable():
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable not found at {EXECUTABLE_PATH}"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File at {EXECUTABLE_PATH} is not executable"


def test_results_file_content():
    assert os.path.isfile(RESULTS_PATH), f"Results file not found at {RESULTS_PATH}"

    expected_content = (
        "Longest Chain Length: 5\n"
        "Top Paper 2019: 101 (1 citations)\n"
        "Top Paper 2020: 103 (3 citations)\n"
        "Top Paper 2021: 105 (2 citations)\n"
        "Top Paper 2022: 111 (2 citations)"
    )

    with open(RESULTS_PATH, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Content of {RESULTS_PATH} does not match expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{actual_content}"
    )


def test_recompile_and_execute_against_multiple_datasets():
    compiled = subprocess.run(
        ["gcc", "-O2", SOURCE_PATH, "-o", EXECUTABLE_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compiled.returncode == 0, (
        f"C source did not compile with the required command.\n"
        f"stdout:\n{compiled.stdout}\nstderr:\n{compiled.stderr}"
    )
    assert os.path.isfile(EXECUTABLE_PATH)
    assert os.access(EXECUTABLE_PATH, os.X_OK)

    cases = [
        ORIGINAL_DATA,
        """9,8,1999
9,7,1999
8,6,2001
7,6,2001
15,14,2000
14,13,2000
13,12,2002
""",
        """999,700,2030
700,500,2031
500,300,2032
300,100,2033
850,100,2030
851,100,2030
852,700,2031
600,400,1987
601,400,1987
602,401,1987
""",
        """40,30,2024
30,20,2024
20,10,2024
90,80,2023
80,70,2023
70,60,2023
60,50,2023
41,10,2024
42,10,2024
91,50,2023
""",
    ]

    try:
        for case in cases:
            run_case(case)
    finally:
        with open(CSV_PATH, "w") as f:
            f.write(ORIGINAL_DATA)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
