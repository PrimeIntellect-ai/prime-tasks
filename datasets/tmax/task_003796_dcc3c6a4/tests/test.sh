#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
from pathlib import Path

PROJECT = Path("/home/user/project")
DATA = PROJECT / "data"
SOURCE = PROJECT / "src/analyzer.cpp"
BINARY = PROJECT / "analyzer"
REPORT = Path("/home/user/output/report.csv")

EXPECTED_MAKEFILE = """CXX = g++
CXXFLAGS = -std=c++17 -O2

all: analyzer

analyzer: src/analyzer.cpp
\t$(CXX) $(CXXFLAGS) -o analyzer src/analyzer.cpp

clean:
\trm -f analyzer
"""


def run_analyzer():
    if REPORT.exists():
        REPORT.unlink()
    result = subprocess.run(
        [str(BINARY)], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"analyzer exited with {result.returncode}: {result.stderr}"
    )
    assert REPORT.is_file(), "analyzer did not create /home/user/output/report.csv"


def read_report():
    with REPORT.open("r") as f:
        return [line.strip() for line in f if line.strip()]


def test_00_source_builds_with_provided_makefile_and_runs():
    assert SOURCE.is_file(), f"Source file missing: {SOURCE}"
    assert not SOURCE.is_symlink(), "src/analyzer.cpp must be a regular source file"
    assert stat.S_ISREG(SOURCE.stat().st_mode), "src/analyzer.cpp is not a regular file"
    assert SOURCE.stat().st_size > 0, "src/analyzer.cpp is empty"

    makefile = PROJECT / "Makefile"
    assert makefile.read_text() == EXPECTED_MAKEFILE, "The provided Makefile was changed"

    if BINARY.exists() or BINARY.is_symlink():
        BINARY.unlink()
    result = subprocess.run(
        ["make"], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"
    assert BINARY.is_file(), "make did not create the analyzer executable"
    assert os.access(BINARY, os.X_OK), "analyzer is not executable"
    with BINARY.open("rb") as f:
        assert f.read(4) == b"\x7fELF", "analyzer is not a compiled ELF executable"

    run_analyzer()


def test_01_report_csv_exists_and_correct():
    report_path = "/home/user/output/report.csv"
    assert os.path.isfile(report_path), f"Report file missing: {report_path}"

    expected_lines = [
        "P5,3",
        "P1,2",
        "P2,1",
        "P4,1"
    ]

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in report.csv, but got {len(lines)}"

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'"


def expected_report(friend_edges, purchases):
    friends = {tuple(sorted(edge)) for edge in friend_edges}
    buyers = {}
    for uid, pid in purchases:
        buyers.setdefault(pid, set()).add(uid)

    results = []
    for pid, users in buyers.items():
        ordered = sorted(users)
        count = sum(
            tuple(sorted((ordered[i], ordered[j]))) in friends
            for i in range(len(ordered))
            for j in range(i + 1, len(ordered))
        )
        if count > 0:
            results.append((pid, count))

    results.sort(key=lambda item: (-item[1], item[0]))
    return [f"{pid},{count}" for pid, count in results[:4]]


def make_random_case(rng):
    while True:
        base = rng.randrange(10000, 90000)
        users = [str(base + i * 7) for i in range(9)]
        token = secrets.token_hex(4)
        products = [f"Q{token}_{i}" for i in range(7)]

        edges = []
        for i in range(len(users)):
            for j in range(i + 1, len(users)):
                if rng.random() < 0.34:
                    edge = (users[i], users[j])
                    if rng.randrange(2):
                        edge = (edge[1], edge[0])
                    edges.append(edge)

        purchases = []
        for pid in products:
            selected = [uid for uid in users if rng.random() < 0.55]
            for uid in selected:
                purchases.append((uid, pid))

        expected = expected_report(edges, purchases)
        cross_join = []
        for pid in products:
            n = len({uid for uid, bought_pid in purchases if bought_pid == pid})
            if n >= 2:
                cross_join.append((pid, n * (n - 1) // 2))
        cross_join.sort(key=lambda item: (-item[1], item[0]))
        cross_lines = [f"{pid},{count}" for pid, count in cross_join[:4]]

        if len(expected) == 4 and expected != cross_lines:
            return users, edges, purchases, expected


def test_02_analyzer_uses_friend_edges_on_unseen_inputs():
    original = {
        name: (DATA / name).read_bytes()
        for name in ("users.csv", "friends.csv", "purchases.csv")
    }
    rng = secrets.SystemRandom()

    try:
        for _ in range(4):
            users, edges, purchases, expected = make_random_case(rng)

            (DATA / "users.csv").write_text(
                "user_id,name\n" + "".join(f"{uid},User{idx}\n" for idx, uid in enumerate(users))
            )
            (DATA / "friends.csv").write_text(
                "user_id_1,user_id_2\n" + "".join(f"{u1},{u2}\n" for u1, u2 in edges)
            )
            (DATA / "purchases.csv").write_text(
                "user_id,product_id\n" + "".join(f"{uid},{pid}\n" for uid, pid in purchases)
            )

            run_analyzer()
            actual = read_report()
            assert actual == expected, (
                "analyzer produced incorrect results for an unseen friendship graph; "
                f"expected {expected}, got {actual}"
            )
    finally:
        for name, contents in original.items():
            (DATA / name).write_bytes(contents)
        run_analyzer()


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
