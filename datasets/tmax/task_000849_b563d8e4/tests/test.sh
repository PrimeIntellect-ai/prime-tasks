#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

SOURCE = "/home/user/aggregate.c"
EXECUTABLE = "/home/user/aggregate"
CATEGORIES = "/home/user/categories.csv"
PAPERS = "/home/user/papers.jsonl"
REPORT = "/home/user/report.txt"

ORIGINAL_EXPECTED = [
    "Biology: 337",
    "Computer Science: 245",
    "Physics: 85",
]


def read_report():
    assert os.path.isfile(REPORT), f"File {REPORT} is missing. Did you run the C program to generate the report?"
    with open(REPORT, "r") as f:
        return [line.strip() for line in f if line.strip()]


def assert_report(expected_lines):
    lines = read_report()
    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {REPORT}, but found {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in {REPORT} is incorrect. Expected '{expected}', got '{actual}'."


def run_program(path, expected_lines):
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run([path], cwd="/home/user", capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"{path} exited with status {result.returncode}: {result.stderr}"
    assert_report(expected_lines)


def test_c_source_file_exists():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing. You must write the C program."


def test_c_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing. Did you compile the C program?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {EXECUTABLE} is not a compiled executable."


def test_report_txt_exists_and_correct():
    assert_report(ORIGINAL_EXPECTED)


def test_program_performs_hierarchical_aggregation():
    saved = {}
    for path in (CATEGORIES, PAPERS, REPORT):
        saved[path] = open(path, "rb").read() if os.path.exists(path) else None

    rebuilt = "/tmp/aggregate_from_source"
    try:
        compile_result = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt], capture_output=True, text=True, timeout=20
        )
        assert compile_result.returncode == 0, f"aggregate.c does not compile: {compile_result.stderr}"

        # Execute both the submitted executable and a fresh build on the supplied data.
        run_program(EXECUTABLE, ORIGINAL_EXPECTED)
        run_program(rebuilt, ORIGINAL_EXPECTED)

        # Use unpredictable names and citation values so a fixed report cannot pass.
        tag = secrets.token_hex(4)
        root_a = f"Alpha_{tag}"
        root_b = f"Omega_{tag}"
        root_c = f"Zeta_{tag}"
        v1 = secrets.randbelow(500) + 11
        v2 = secrets.randbelow(500) + 17
        v3 = secrets.randbelow(500) + 23
        v4 = secrets.randbelow(500) + 29
        v5 = secrets.randbelow(500) + 31

        categories = [
            (101, None, root_b),
            (202, None, root_a),
            (303, 101, "Level One"),
            (404, 303, "Level Two"),
            (505, 404, "Level Three"),
            (606, 202, "Other Child"),
            (707, None, root_c),
        ]
        papers = [
            ("x1", 505, v1),
            ("x2", 303, v2),
            ("x3", 101, v3),
            ("x4", 606, v4),
            ("x5", 707, v5),
        ]

        with open(CATEGORIES, "w") as f:
            f.write("id,parent_id,name\n")
            for cid, parent, name in categories:
                f.write(f"{cid},{'' if parent is None else parent},{name}\n")
        with open(PAPERS, "w") as f:
            for pid, category_id, citations in papers:
                f.write(f'{{"id": "{pid}", "category_id": {category_id}, "citations": {citations}}}\n')

        parents = {cid: parent for cid, parent, _ in categories}
        names = {cid: name for cid, _, name in categories}
        totals = {}
        for _, category_id, citations in papers:
            root = category_id
            while parents[root] is not None:
                root = parents[root]
            totals[names[root]] = totals.get(names[root], 0) + citations
        expected = [f"{name}: {totals[name]}" for name in sorted(totals)]

        run_program(EXECUTABLE, expected)
        run_program(rebuilt, expected)
    finally:
        for path, data in saved.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
        if os.path.exists(rebuilt):
            os.remove(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
