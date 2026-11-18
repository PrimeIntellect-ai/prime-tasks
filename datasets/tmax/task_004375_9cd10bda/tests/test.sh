#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess


def read_report(path):
    with open(path, "r") as f:
        content = f.read().strip().splitlines()
    return [line.strip() for line in content if line.strip()]


def test_deadlock_report_exists_and_correct():
    report_path = "/home/user/deadlock_report.txt"

    assert os.path.isfile(report_path), f"Expected output file {report_path} does not exist."

    expected_lines = [
        "T1:2",
        "T2:1",
        "T3:1",
        "T6:1",
        "T7:1",
        "T9:1"
    ]

    content = read_report(report_path)

    assert content == expected_lines, (
        f"Contents of {report_path} do not match the expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Got: {content}"
    )


def test_cpp_source_and_executable_exist():
    cpp_path = "/home/user/detect_deadlocks.cpp"
    exe_path = "/home/user/detect_deadlocks"

    assert os.path.isfile(cpp_path), f"C++ source file {cpp_path} is missing."
    assert os.path.isfile(exe_path), f"Compiled executable {exe_path} is missing."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."


def expected_report(rows):
    holders = {}
    transactions = set()
    for tx, held, waited in rows:
        transactions.add(tx)
        if held:
            holders.setdefault(held, set()).add(tx)

    graph = {tx: set() for tx in transactions}
    for tx, held, waited in rows:
        if waited:
            graph[tx].update(holders.get(waited, set()))

    deadlocked = set()
    for start in transactions:
        stack = list(graph[start])
        seen = set()
        while stack:
            node = stack.pop()
            if node == start:
                deadlocked.add(start)
                break
            if node not in seen:
                seen.add(node)
                stack.extend(graph.get(node, ()))

    return [f"{tx}:{len(graph[tx])}" for tx in sorted(deadlocked)]


def write_locks(path, rows):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["tx_id", "holds_resource", "waits_for_resource"])
        writer.writerows(rows)


def test_program_is_compiled_and_analyzes_varied_csv_inputs():
    cpp_path = "/home/user/detect_deadlocks.cpp"
    exe_path = "/home/user/detect_deadlocks"
    locks_path = "/home/user/locks.csv"
    report_path = "/home/user/deadlock_report.txt"

    subprocess.run(
        ["g++", "-std=c++17", cpp_path, "-o", exe_path],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )

    with open(locks_path, "rb") as f:
        original_locks = f.read()
    with open(report_path, "rb") as f:
        original_report = f.read()

    token = secrets.token_hex(4)
    def tx(label):
        return f"{label}_{token}"
    def res(label):
        return f"RES_{label}_{token}"

    cases = [
        [
            (tx("A"), res("A"), ""),
            (tx("B"), res("B"), ""),
            (tx("C"), res("C"), ""),
            (tx("D"), res("D"), ""),
            (tx("A"), "", res("B")),
            (tx("B"), "", res("C")),
            (tx("D"), "", res("UNHELD")),
        ],
        [
            (tx("J"), res("J"), ""),
            (tx("K"), res("K1"), ""),
            (tx("K"), res("K2"), ""),
            (tx("L"), res("L"), ""),
            (tx("M"), res("M"), ""),
            (tx("N"), res("N"), ""),
            (tx("J"), "", res("K1")),
            (tx("J"), "", res("K2")),
            (tx("J"), "", res("M")),
            (tx("K"), "", res("L")),
            (tx("L"), "", res("J")),
            (tx("M"), "", res("N")),
            (tx("N"), "", res("N")),
        ],
        [
            (tx("P"), res("P"), ""),
            (tx("Q"), res("Q"), ""),
            (tx("R"), res("R"), ""),
            (tx("S"), res("S"), ""),
            (tx("U"), res("U"), ""),
            (tx("P"), "", res("Q")),
            (tx("Q"), "", res("P")),
            (tx("Q"), "", res("R")),
            (tx("R"), "", res("S")),
            (tx("S"), "", res("R")),
            (tx("U"), "", res("P")),
        ],
    ]

    try:
        for rows in cases:
            secrets.SystemRandom().shuffle(rows)
            expected = expected_report(rows)
            write_locks(locks_path, rows)
            if os.path.exists(report_path):
                os.unlink(report_path)

            result = subprocess.run(
                [exe_path],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"Program exited with {result.returncode}.\n"
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
            )
            assert os.path.isfile(report_path), "Program did not create deadlock_report.txt"
            actual = read_report(report_path)
            assert actual == expected, (
                f"Incorrect report for dynamically generated locks.csv.\n"
                f"Expected: {expected}\nGot: {actual}"
            )
    finally:
        with open(locks_path, "wb") as f:
            f.write(original_locks)
        with open(report_path, "wb") as f:
            f.write(original_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
