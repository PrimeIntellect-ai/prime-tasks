#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_etl_ast.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)

func main() {
    if len(os.Args) < 2 {
        os.Exit(2)
    }
    path := os.Args[len(os.Args)-1]
    f, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(2)
    }

    hasSHA256 := false
    for _, imp := range f.Imports {
        p, err := strconv.Unquote(imp.Path.Value)
        if err == nil && p == "crypto/sha256" {
            hasSHA256 = true
        }
    }

    hasGoStmt := false
    ast.Inspect(f, func(n ast.Node) bool {
        if _, ok := n.(*ast.GoStmt); ok {
            hasGoStmt = true
        }
        return true
    })

    if !hasSHA256 {
        fmt.Fprintln(os.Stderr, "etl.go does not import crypto/sha256")
        os.Exit(3)
    }
    if !hasGoStmt {
        fmt.Fprintln(os.Stderr, "etl.go does not contain a goroutine launch")
        os.Exit(4)
    }
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile

import pytest

LOG_DIR = "/home/user/data/logs"
CSV_PATH = "/home/user/output/metrics.csv"
ETL_PATH = "/home/user/etl.go"
SCRIPT_PATH = "/home/user/run_etl.sh"


def run_checked(command, timeout=90):
    result = subprocess.run(
        command,
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=timeout,
        env={**os.environ, "HOME": "/home/user"},
    )
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_nonempty_lines():
    assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} does not exist."
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def replace_logs(files):
    shutil.rmtree(LOG_DIR, ignore_errors=True)
    os.makedirs(LOG_DIR, exist_ok=True)
    for name, lines in files.items():
        with open(os.path.join(LOG_DIR, name), "w", encoding="utf-8", newline="\n") as f:
            for line in lines:
                f.write(line + "\n")


def original_fixture():
    return {
        "log_1.jsonl": [
            '{"timestamp": 1700000000, "cpu_usage": 50.0, "message": "status ok"}',
            '{"timestamp": 1700000010, "cpu_usage": 60.0, "message": "status ok"}',
            '{"timestamp": 1700000000, "cpu_usage": 50.0, "message": "status ok"}',
            '{"timestamp": 1700000020, "cpu_usage": 70.0, "message": "bad unicode \\uZZZZ"}',
        ],
        "log_2.jsonl": [
            '{"timestamp": 1700000030, "cpu_usage": 80.0, "message": "status ok"}',
            '{"timestamp": 1700000020, "cpu_usage": 70.0, "message": "bad unicode \\uZZZZ"}',
            '{"timestamp": 1700000040, "cpu_usage": 90.0, "message": "status ok"}',
        ],
    }


def randomized_fixture():
    rng = random.SystemRandom()
    base = 1800000000 + rng.randrange(1000000)
    timestamps = [base + offset for offset in (37, 5, 81, 19, 64, 48, 96)]
    values = [float(rng.randrange(1000, 9001)) / 100.0 for _ in timestamps]

    unique = []
    for i, (timestamp, value) in enumerate(zip(timestamps, values)):
        message = "bad unicode \\uXYZW" if i in (2, 5) else f"status {rng.randrange(1000000)}"
        unique.append(
            f'{{"timestamp": {timestamp}, "cpu_usage": {value:.2f}, "message": "{message}"}}'
        )

    first = [unique[0], unique[3], unique[5], unique[1]]
    second = [unique[2], unique[4], unique[6], unique[1], unique[5]]
    rng.shuffle(first)
    rng.shuffle(second)

    # A valid-looking non-jsonl file must not be processed.
    decoy = ['{"timestamp": 1, "cpu_usage": 99.99, "message": "ignore me"}']
    files = {"alpha.jsonl": first, "beta.jsonl": second, "ignored.txt": decoy}
    return files, expected_from_fixture(files)


def expected_from_fixture(files):
    seen = set()
    records = []
    ts_re = re.compile(r'"timestamp"\s*:\s*([0-9]+)')
    cpu_re = re.compile(r'"cpu_usage"\s*:\s*([-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))')

    for name, lines in files.items():
        if not name.endswith(".jsonl"):
            continue
        for raw in lines:
            digest = hashlib.sha256(raw.encode("utf-8")).digest()
            if digest in seen:
                continue
            seen.add(digest)
            ts_match = ts_re.search(raw)
            cpu_match = cpu_re.search(raw)
            assert ts_match and cpu_match
            records.append((int(ts_match.group(1)), float(cpu_match.group(1))))

    records.sort(key=lambda item: item[0])
    expected = ["timestamp,cpu_usage,rolling_avg"]
    for i, (timestamp, cpu) in enumerate(records):
        window = records[max(0, i - 2):i + 1]
        average = sum(value for _, value in window) / len(window)
        expected.append(f"{timestamp},{cpu:.2f},{average:.2f}")
    return expected


def test_pipeline_artifacts_and_behavior():
    assert os.path.isfile(ETL_PATH), f"Go source {ETL_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    temp_root = tempfile.mkdtemp(prefix="etl-verifier-")
    saved_logs = os.path.join(temp_root, "logs")
    if os.path.isdir(LOG_DIR):
        shutil.copytree(LOG_DIR, saved_logs)
    saved_source = open(ETL_PATH, "rb").read()
    source_mode = stat.S_IMODE(os.stat(ETL_PATH).st_mode)
    had_csv = os.path.isfile(CSV_PATH)
    saved_csv = open(CSV_PATH, "rb").read() if had_csv else b""

    try:
        # The source must be valid Go and retain the required hash and goroutine mechanisms.
        run_checked(["go", "run", "/tmp/check_etl_ast.go", "--", ETL_PATH])
        run_checked(["go", "build", "-o", "/tmp/submission_etl", ETL_PATH])

        # Preserve the original exact-output assertion, but generate it by running the pipeline.
        replace_logs(original_fixture())
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        run_checked([SCRIPT_PATH])
        expected_original = [
            "timestamp,cpu_usage,rolling_avg",
            "1700000000,50.00,50.00",
            "1700000010,60.00,55.00",
            "1700000020,70.00,60.00",
            "1700000030,80.00,70.00",
            "1700000040,90.00,80.00",
        ]
        assert read_nonempty_lines() == expected_original

        # Exercise the compiled submitted program on an unpredictable fixture.
        files, expected = randomized_fixture()
        replace_logs(files)
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        run_checked(["/tmp/submission_etl"])
        assert read_nonempty_lines() == expected

        # The scheduling wrapper must also produce the derived result on that fixture.
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        run_checked([SCRIPT_PATH])
        assert read_nonempty_lines() == expected

        # Verify that run_etl.sh actually compiles and runs /home/user/etl.go.
        probe = "/tmp/run_etl_source_probe"
        if os.path.exists(probe):
            os.remove(probe)
        sentinel = '''package main
import "os"
func main() {
    if err := os.WriteFile("/tmp/run_etl_source_probe", []byte("ran"), 0644); err != nil { panic(err) }
}
'''
        with open(ETL_PATH, "w", encoding="utf-8") as f:
            f.write(sentinel)
        run_checked([SCRIPT_PATH])
        assert os.path.isfile(probe), (
            "run_etl.sh did not compile and run /home/user/etl.go"
        )
    finally:
        with open(ETL_PATH, "wb") as f:
            f.write(saved_source)
        os.chmod(ETL_PATH, source_mode)
        shutil.rmtree(LOG_DIR, ignore_errors=True)
        if os.path.isdir(saved_logs):
            shutil.copytree(saved_logs, LOG_DIR)
        else:
            os.makedirs(LOG_DIR, exist_ok=True)
        os.makedirs(os.path.dirname(CSV_PATH), exist_ok=True)
        if had_csv:
            with open(CSV_PATH, "wb") as f:
                f.write(saved_csv)
        elif os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        for path in ("/tmp/submission_etl", "/tmp/run_etl_source_probe"):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        shutil.rmtree(temp_root, ignore_errors=True)


def test_crontab_entry():
    try:
        result = subprocess.run(
            ["crontab", "-l", "-u", "user"], capture_output=True, text=True
        )
        if result.returncode != 0:
            result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    except Exception:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)

    found = False
    for line in result.stdout.splitlines():
        parts = line.split()
        if (
            len(parts) >= 6
            and parts[:5] == ["*/15", "*", "*", "*", "*"]
            and parts[5] == "/home/user/run_etl.sh"
        ):
            found = True
            break
    assert found, "Crontab entry '*/15 * * * * /home/user/run_etl.sh' not found."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
