#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import hashlib
import json
import os
import shutil
import subprocess
import textwrap
import pytest

CSV_FILE = "/home/user/config_history.csv"
TRACKER_FILE = "/home/user/tracker.go"
DUMP_DIR = "/home/user/config_dumps"
BINARY_FILE = "/tmp/tracker_submission"


def get_expected_data():
    # Defined by the problem statement and truth data
    raw_states = [
        (1600000000, "localhost", 5432, 100),
        (1600000060, "localhost", 5432, 100),
        (1600000120, "db.internal", 5432, 100),
        (1600000180, "db.internal", 5432, 100),
        (1600000240, "db.internal", 5432, 200),
        (1600000300, "localhost", 5432, 100),
    ]

    raw_states.sort(key=lambda x: x[0])
    deduped_states = []
    last_hash = None

    for ts, host, port, max_conn in raw_states:
        hash_str = f"{host}:{port}:{max_conn}"
        curr_hash = hashlib.sha256(hash_str.encode("utf-8")).hexdigest()
        if curr_hash != last_hash:
            deduped_states.append({
                "timestamp": str(ts),
                "db_host": host,
                "db_port": str(port),
                "max_connections": str(max_conn),
                "config_hash": curr_hash,
            })
            last_hash = curr_hash

    return deduped_states


def read_csv():
    with open(CSV_FILE, "r", newline="") as f:
        return list(csv.DictReader(f))


def expected_from_states(states):
    result = []
    previous_hash = None
    for timestamp, host, port, max_connections, _ in sorted(states):
        digest = hashlib.sha256(
            f"{host}:{port}:{max_connections}".encode("utf-8")
        ).hexdigest()
        if digest != previous_hash:
            result.append({
                "timestamp": str(timestamp),
                "db_host": host,
                "db_port": str(port),
                "max_connections": str(max_connections),
                "config_hash": digest,
            })
            previous_hash = digest
    return result


def test_csv_file_exists():
    assert os.path.isfile(CSV_FILE), f"The output file {CSV_FILE} was not found."


def test_csv_headers():
    with open(CSV_FILE, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail(f"{CSV_FILE} is empty.")

    expected_headers = ["timestamp", "db_host", "db_port", "max_connections", "config_hash"]
    assert headers == expected_headers, f"CSV headers do not match. Expected {expected_headers}, got {headers}."


def test_csv_content_deduplicated_and_hashed():
    expected_data = get_expected_data()
    actual_data = read_csv()

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} rows of data (excluding header), got {len(actual_data)}."
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."


def test_tracker_exists_compiles_uses_goroutine_and_processes_new_dumps():
    assert os.path.isfile(TRACKER_FILE), f"Required Go source {TRACKER_FILE} was not found."

    checker = r'''
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    f, err := parser.ParseFile(token.NewFileSet(), "/home/user/tracker.go", nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }
    found := false
    ast.Inspect(f, func(n ast.Node) bool {
        if _, ok := n.(*ast.GoStmt); ok {
            found = true
        }
        return true
    })
    if !found {
        fmt.Fprintln(os.Stderr, "tracker.go contains no Go goroutine statement")
        os.Exit(1)
    }
}
'''
    checker_path = "/tmp/check_tracker_concurrency.go"
    with open(checker_path, "w") as f:
        f.write(checker)

    subprocess.run(
        ["go", "run", checker_path],
        check=True,
        cwd="/home/user",
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    subprocess.run(
        ["go", "build", "-o", BINARY_FILE, TRACKER_FILE],
        check=True,
        cwd="/home/user",
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    states = [
        (1700000300, "gamma.internal", 6432, 310, "txt"),
        (1700000000, "alpha.internal", 5433, 150, "json"),
        (1700000180, "beta.internal", 6432, 275, "txt"),
        (1700000060, "alpha.internal", 5433, 150, "txt"),
        (1700000240, "gamma.internal", 6432, 310, "json"),
        (1700000120, "beta.internal", 6432, 275, "json"),
        (1700000360, "alpha.internal", 5433, 150, "json"),
    ]

    for entry in os.listdir(DUMP_DIR):
        path = os.path.join(DUMP_DIR, entry)
        if os.path.isdir(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    for timestamp, host, port, max_connections, kind in states:
        path = os.path.join(DUMP_DIR, f"dump_{timestamp}.{kind}")
        if kind == "json":
            with open(path, "w") as f:
                json.dump({
                    "db_host": host,
                    "db_port": port,
                    "max_connections": max_connections,
                    "ignored": "value",
                }, f)
        else:
            with open(path, "w") as f:
                f.write(textwrap.dedent(f"""\
                    db_host={host}
                    db_port={port}
                    max_connections={max_connections}
                    ignored=value
                """))

    if os.path.exists(CSV_FILE):
        os.unlink(CSV_FILE)

    subprocess.run(
        [BINARY_FILE],
        check=True,
        cwd="/home/user",
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    assert os.path.isfile(CSV_FILE), "Running tracker.go did not create config_history.csv."
    with open(CSV_FILE, "r", newline="") as f:
        reader = csv.reader(f)
        headers = next(reader, None)
    expected_headers = ["timestamp", "db_host", "db_port", "max_connections", "config_hash"]
    assert headers == expected_headers

    expected = expected_from_states(states)
    actual = read_csv()
    assert actual == expected, f"Tracker output for newly generated dump files was incorrect. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
