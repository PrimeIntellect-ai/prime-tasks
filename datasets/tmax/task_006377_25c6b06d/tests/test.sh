#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess
import tempfile
from collections import defaultdict

import pytest


def test_c_source_exists():
    path = "/home/user/graph_analyzer.c"
    assert os.path.exists(path), f"Source file {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."


def test_executable_exists():
    path = "/home/user/graph_analyzer"
    assert os.path.exists(path), f"Executable {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def compute_expected(input_csv, min_strength, top_k):
    node_strengths = defaultdict(int)
    with open(input_csv, "r", newline="") as f:
        reader = csv.reader(f)
        first = True
        for row in reader:
            if not row or len(row) < 4:
                continue
            if first and row[0].strip().lower() == "timestamp":
                first = False
                continue
            first = False
            try:
                bytes_transferred = int(row[3])
            except ValueError:
                continue
            node_strengths[row[1]] += bytes_transferred
            node_strengths[row[2]] += bytes_transferred

    result = [(ip, strength) for ip, strength in node_strengths.items()
              if strength >= min_strength]
    result.sort(key=lambda x: (-x[1], x[0]))
    return result[:top_k]


def read_actual(output_csv="/home/user/top_nodes.csv"):
    assert os.path.exists(output_csv), f"Output file {output_csv} does not exist."
    assert os.path.isfile(output_csv), f"{output_csv} is not a file."
    actual = []
    with open(output_csv, "r", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            assert len(row) == 2, f"Row in {output_csv} does not have exactly 2 columns: {row}"
            ip = row[0].strip()
            try:
                strength = int(row[1].strip())
            except ValueError:
                pytest.fail(f"Invalid strength value in {output_csv}: {row[1]}")
            actual.append((ip, strength))
    return actual


def test_top_nodes_csv_content():
    input_csv = "/home/user/network_traffic.csv"
    output_csv = "/home/user/top_nodes.csv"

    assert os.path.exists(output_csv), f"Output file {output_csv} does not exist."
    assert os.path.isfile(output_csv), f"{output_csv} is not a file."
    assert os.path.exists(input_csv), f"Input file {input_csv} is missing."

    expected_top_nodes = compute_expected(input_csv, 1000, 2)
    actual_top_nodes = read_actual(output_csv)

    assert actual_top_nodes == expected_top_nodes, (
        f"Content of {output_csv} is incorrect.\n"
        f"Expected: {expected_top_nodes}\n"
        f"Actual: {actual_top_nodes}"
    )


def run_valid(binary, input_path, min_strength, top_k):
    output = "/home/user/top_nodes.csv"
    if os.path.exists(output):
        os.unlink(output)
    proc = subprocess.run(
        [binary, input_path, str(min_strength), str(top_k)],
        cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=5
    )
    assert proc.returncode == 0, (
        f"{binary} failed for valid arguments with exit code {proc.returncode}: "
        f"{proc.stderr}"
    )
    expected = compute_expected(input_path, min_strength, top_k)
    actual = read_actual(output)
    assert actual == expected, (
        f"Incorrect output from {binary} for filter={min_strength}, top_k={top_k}.\n"
        f"Expected: {expected}\nActual: {actual}"
    )


def test_program_execution_and_arguments():
    installed = "/home/user/graph_analyzer"
    source = "/home/user/graph_analyzer.c"

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "graph_analyzer_from_source")
        compile_proc = subprocess.run(
            ["gcc", source, "-o", rebuilt], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=15
        )
        assert compile_proc.returncode == 0, f"C source does not compile with gcc: {compile_proc.stderr}"

        # Execute the exact requested query using the submitted executable.
        run_valid(installed, "/home/user/network_traffic.csv", 1000, 2)

        token = secrets.randbelow(180) + 20
        ips = [f"10.{token}.0.{i}" for i in range(1, 7)]
        weights = [secrets.randbelow(700) + 101 for _ in range(7)]
        rows = [
            ["1700000000", ips[0], ips[1], str(weights[0]), "TCP"],
            ["1700000001", ips[1], ips[2], str(weights[1]), "UDP"],
            ["1700000002", ips[0], ips[2], str(weights[2]), "TCP"],
            ["1700000003", ips[3], ips[0], str(weights[3]), "ICMP"],
            ["1700000004", ips[4], ips[1], str(weights[4]), "TCP"],
            ["1700000005", ips[5], ips[4], str(weights[5]), "UDP"],
            ["1700000006", ips[2], ips[5], str(weights[6]), "TCP"],
        ]
        generated = os.path.join(td, "generated.csv")
        with open(generated, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["timestamp", "src_ip", "dst_ip", "bytes", "protocol"])
            writer.writerows(rows)

        strengths = defaultdict(int)
        for row in rows:
            strengths[row[1]] += int(row[3])
            strengths[row[2]] += int(row[3])
        exact_boundary = max(strengths.values())

        tie_weight = secrets.randbelow(800) + 200
        tie_ips = [f"192.0.{token}.{i}" for i in (40, 10, 30, 20)]
        no_header = os.path.join(td, "no_header.csv")
        with open(no_header, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["1800000000", tie_ips[0], tie_ips[1], tie_weight, "TCP"])
            writer.writerow(["1800000001", tie_ips[2], tie_ips[3], tie_weight, "UDP"])

        for binary in (installed, rebuilt):
            run_valid(binary, generated, 0, 2)
            run_valid(binary, generated, exact_boundary, 10)
            run_valid(binary, no_header, tie_weight, 3)

            bad_commands = [
                [binary],
                [binary, generated, "0"],
                [binary, generated, "0", "2", "extra"],
            ]
            for command in bad_commands:
                proc = subprocess.run(
                    command, cwd="/home/user", stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE, text=True, timeout=5
                )
                assert proc.returncode != 0, (
                    f"{binary} accepted an invalid argument count: {command[1:]}"
                )

    # Leave the required final output produced by the submitted executable.
    run_valid(installed, "/home/user/network_traffic.csv", 1000, 2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
