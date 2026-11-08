#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'GO_EOF' > /tmp/check_concurrency.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    target := os.Getenv("TARGET_GO_FILE")
    f, err := parser.ParseFile(token.NewFileSet(), target, nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    concurrent := false
    ast.Inspect(f, func(n ast.Node) bool {
        if _, ok := n.(*ast.GoStmt); ok {
            concurrent = true
        }
        // Also accept the common errgroup.Group.Go concurrency pattern.
        if call, ok := n.(*ast.CallExpr); ok {
            if sel, ok := call.Fun.(*ast.SelectorExpr); ok && sel.Sel.Name == "Go" {
                concurrent = true
            }
        }
        return true
    })

    if !concurrent {
        fmt.Fprintln(os.Stderr, "process_logs.go contains no goroutine or Group.Go invocation")
        os.Exit(1)
    }
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import subprocess
from datetime import datetime, timezone

import pytest

PROGRAM = "/home/user/process_logs.go"
OUTPUT = "/home/user/trace_summary.json"
LOG_DIR = "/home/user/raw_logs"


def run_program():
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        ["go", "run", PROGRAM],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        "process_logs.go failed when executed.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), "The file /home/user/trace_summary.json is missing."

    try:
        with open(OUTPUT, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail("The file /home/user/trace_summary.json is not valid JSON.")


def assert_summary(data, expected_data):
    assert isinstance(data, list), "The JSON root must be an array."
    assert len(data) == len(expected_data), (
        f"Expected {len(expected_data)} traces, but found {len(data)}."
    )

    trace_ids = [item.get("trace_id") for item in data]
    assert trace_ids == sorted(trace_ids), (
        "The JSON array is not sorted alphabetically by trace_id."
    )

    for i in range(len(expected_data)):
        assert data[i] == expected_data[i], (
            f"Mismatch at index {i}. Expected {expected_data[i]}, got {data[i]}."
        )


def write_fixture(auth_lines, db_lines, api_lines):
    os.makedirs(LOG_DIR, exist_ok=True)
    for name, lines in (
        ("auth.log", auth_lines),
        ("db.log", db_lines),
        ("api.log", api_lines),
    ):
        with open(os.path.join(LOG_DIR, name), "w") as f:
            f.write("\n".join(lines))
            if lines:
                f.write("\n")


def expected_from_events(events):
    grouped = {}
    for event in events:
        item = grouped.setdefault(event["trace_id"], {
            "times": [],
            "max_db_query_ms": 0,
            "has_error": False,
        })
        item["times"].append(event["timestamp"])
        if event["kind"] == "db":
            item["max_db_query_ms"] = max(
                item["max_db_query_ms"], event["query_time_ms"]
            )
        elif event["kind"] == "auth" and event["status"] == "FAIL":
            item["has_error"] = True
        elif event["kind"] == "api" and event["http_status_code"] >= 400:
            item["has_error"] = True

    result = []
    for trace_id in sorted(grouped):
        item = grouped[trace_id]
        result.append({
            "trace_id": trace_id,
            "duration_ms": (max(item["times"]) - min(item["times"])) * 1000,
            "max_db_query_ms": item["max_db_query_ms"],
            "has_error": item["has_error"],
        })
    return result


def make_random_fixture(rng, round_number):
    trace_ids = sorted({
        f"R{round_number}_{rng.randrange(10**7, 10**8)}" for _ in range(8)
    })
    assert len(trace_ids) >= 5
    trace_ids = trace_ids[:5]
    base = 1697000000 + rng.randrange(1000, 50000)

    auth_lines, db_lines, api_lines, events = [], [], [], []

    for i, trace_id in enumerate(trace_ids):
        origin = base + i * 31

        if i != 4:
            ts = origin + rng.randrange(0, 5)
            status = "FAIL" if i == 1 else "SUCCESS"
            stamp = datetime.fromtimestamp(ts, timezone.utc).strftime("%Y/%m/%d %H:%M:%S")
            auth_lines.append(f"{stamp} | {trace_id} | {status}")
            events.append({"kind": "auth", "trace_id": trace_id, "timestamp": ts, "status": status})

        if i in (0, 1, 3):
            for offset in (rng.randrange(5, 9), rng.randrange(10, 15)):
                ts = origin + offset
                query_ms = rng.randrange(17, 900)
                db_lines.append(f"{ts} | {trace_id} | {query_ms}")
                events.append({
                    "kind": "db", "trace_id": trace_id, "timestamp": ts,
                    "query_time_ms": query_ms,
                })

        if i in (0, 2, 3, 4):
            ts = origin + rng.randrange(15, 24)
            code = 503 if i == 2 else 200 + i
            stamp = datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            api_lines.append(f"{stamp} | {trace_id} | /route/{i} | {code}")
            events.append({
                "kind": "api", "trace_id": trace_id, "timestamp": ts,
                "http_status_code": code,
            })

    rng.shuffle(auth_lines)
    rng.shuffle(db_lines)
    rng.shuffle(api_lines)
    return auth_lines, db_lines, api_lines, expected_from_events(events)


def test_pipeline_program_and_output():
    assert os.path.exists(PROGRAM), "The file /home/user/process_logs.go is missing."
    mode = os.lstat(PROGRAM).st_mode
    assert stat.S_ISREG(mode), "/home/user/process_logs.go must be a regular Go source file."

    env = os.environ.copy()
    env["TARGET_GO_FILE"] = PROGRAM
    concurrency = subprocess.run(
        ["go", "run", "/tmp/check_concurrency.go"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=30,
    )
    assert concurrency.returncode == 0, concurrency.stderr

    # Preserve the original fixture and its exact expected assertions.
    write_fixture(
        [
            "2023/10/01 10:00:00 | T100 | SUCCESS",
            "2023/10/01 10:00:05 | T101 | FAIL",
            "2023/10/01 10:00:10 | T102 | SUCCESS",
        ],
        [
            "1696154402 | T100 | 45",
            "1696154406 | T101 | 120",
            "1696154403 | T100 | 30",
            "1696154415 | T102 | 200",
        ],
        [
            "2023-10-01T10:00:01Z | T100 | /users | 200",
            "2023-10-01T10:00:07Z | T101 | /checkout | 500",
            "2023-10-01T10:00:11Z | T102 | /process | 201",
            "2023-10-01T10:00:16Z | T102 | /confirm | 200",
        ],
    )
    expected_data = [
        {"trace_id": "T100", "duration_ms": 3000, "max_db_query_ms": 45, "has_error": False},
        {"trace_id": "T101", "duration_ms": 2000, "max_db_query_ms": 120, "has_error": True},
        {"trace_id": "T102", "duration_ms": 6000, "max_db_query_ms": 200, "has_error": False},
    ]
    assert_summary(run_program(), expected_data)

    # Exercise fresh, unpredictable logs so a prewritten JSON answer cannot pass.
    rng = random.SystemRandom()
    for round_number in range(2):
        auth, db, api, expected = make_random_fixture(rng, round_number)
        write_fixture(auth, db, api)
        assert_summary(run_program(), expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
