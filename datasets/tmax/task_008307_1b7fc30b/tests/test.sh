#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import secrets
import sqlite3
import subprocess
import textwrap

import pytest

DB_PATH = "/home/user/research.db"
RESULTS_PATH = "/home/user/results.json"
SOURCE_PATH = "/home/user/process.go"
BINARY_PATH = "/tmp/process_submission"


def inspect_go_source():
    assert os.path.isfile(SOURCE_PATH), f"Go source file missing at {SOURCE_PATH}"
    assert not os.path.islink(SOURCE_PATH), f"{SOURCE_PATH} must be a regular source file"

    checker = r'''
package main

import (
    "encoding/json"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
    "strings"
)

type Result struct {
    Strings       string `json:"strings"`
    HasZeroCompare bool  `json:"has_zero_compare"`
}

func zero(e ast.Expr) bool {
    lit, ok := e.(*ast.BasicLit)
    if !ok || (lit.Kind != token.INT && lit.Kind != token.FLOAT) {
        return false
    }
    s := strings.ReplaceAll(lit.Value, "_", "")
    v, err := strconv.ParseFloat(s, 64)
    return err == nil && v == 0
}

func main() {
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil {
        panic(err)
    }
    out := Result{}
    var values []string
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.BasicLit:
            if x.Kind == token.STRING {
                if s, err := strconv.Unquote(x.Value); err == nil {
                    values = append(values, s)
                }
            }
        case *ast.BinaryExpr:
            if x.Op == token.LSS || x.Op == token.LEQ || x.Op == token.GTR || x.Op == token.GEQ {
                if zero(x.X) || zero(x.Y) {
                    out.HasZeroCompare = true
                }
            }
        }
        return true
    })
    out.Strings = strings.Join(values, "\n")
    json.NewEncoder(os.Stdout).Encode(out)
}
'''
    with open("/tmp/inspect_process.go", "w") as f:
        f.write(checker)
    proc = subprocess.run(
        ["go", "run", "/tmp/inspect_process.go", SOURCE_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert proc.returncode == 0, f"process.go could not be parsed as Go source:\n{proc.stderr}"
    info = json.loads(proc.stdout)
    literals = info["strings"].upper()

    assert re.search(r"SUM\s*\(.*?\)\s*OVER\s*(?:\(|[A-Z_])", literals, re.S), \
        "process.go must contain a SQL SUM(...) OVER (...) window expression"
    assert "ORDER BY" in literals, "The SQL window query must specify chronological ordering"
    assert re.search(r"DROP\s+INDEX\s+IF\s+EXISTS\s+IDX_METRICS_NODE", literals) or re.search(r"\bNOT\s+INDEXED\b", literals), \
        "process.go must bypass idx_metrics_node using DROP INDEX IF EXISTS or NOT INDEXED"
    assert "DEPENDS_ON" in literals and "ROOT" in literals, \
        "process.go must query ROOT's depends_on targets"
    assert info["has_zero_compare"], \
        "process.go must contain executable Go comparison logic against zero for filtering cumulative scores"


def compile_submission():
    proc = subprocess.run(
        ["go", "build", "-o", BINARY_PATH, SOURCE_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert proc.returncode == 0, f"process.go failed to compile:\n{proc.stdout}{proc.stderr}"
    assert os.path.isfile(BINARY_PATH), "Compilation did not produce an executable"


def make_case(case_number):
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass

    tag = secrets.token_hex(5)
    targets = [f"N_{tag}_{x}" for x in ("zeta", "alpha", "middle")]
    p = 3 + secrets.randbelow(8)
    q = 2 + secrets.randbelow(7)

    metrics = {
        targets[0]: [p, -(p + 2), p + 5],
        targets[1]: [-q, q - 1, 5],
        targets[2]: [1 + case_number, 2, -1],
    }
    dates = [f"202{case_number + 3}-02-01", f"202{case_number + 3}-02-03", f"202{case_number + 3}-02-08"]

    conn = sqlite3.connect(DB_PATH)
    conn.executescript("""
        CREATE TABLE nodes (id TEXT PRIMARY KEY, type TEXT);
        CREATE TABLE edges (source TEXT, target TEXT, relation TEXT);
        CREATE TABLE metrics (node_id TEXT, score REAL, recorded_at DATETIME);
    """)
    conn.execute("INSERT INTO nodes VALUES ('ROOT', 'core')")
    for node in targets:
        conn.execute("INSERT INTO nodes VALUES (?, 'concept')", (node,))
        conn.execute("INSERT INTO edges VALUES ('ROOT', ?, 'depends_on')", (node,))
    unrelated = f"UNRELATED_{tag}"
    conn.execute("INSERT INTO nodes VALUES (?, 'concept')", (unrelated,))
    conn.execute("INSERT INTO edges VALUES ('ROOT', ?, 'relates_to')", (unrelated,))
    conn.execute("INSERT INTO metrics VALUES (?, 9999, ?)", (unrelated, dates[0]))
    conn.execute("INSERT INTO metrics VALUES (?, 7777, ?)", (targets[0], f"2022-01-01"))
    conn.execute("DELETE FROM metrics WHERE recorded_at = '2022-01-01'")

    expected = []
    for node, scores in metrics.items():
        cumulative = 0.0
        for date, score in zip(dates, scores):
            conn.execute("INSERT INTO metrics VALUES (?, ?, ?)", (node, score, date))
            cumulative += score
            if cumulative >= 0.0:
                expected.append({
                    "node_id": node,
                    "recorded_at": date,
                    "cumulative_score": float(cumulative),
                })
    conn.execute("CREATE INDEX idx_metrics_node ON metrics(node_id)")
    conn.commit()
    conn.close()
    expected.sort(key=lambda x: (x["node_id"], x["recorded_at"]))
    return expected


def run_submission():
    try:
        os.remove(RESULTS_PATH)
    except FileNotFoundError:
        pass
    proc = subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, f"Compiled program failed:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"


def assert_results(expected_data):
    # Preserve the original verifier's existence and content assertions.
    assert os.path.exists(RESULTS_PATH), f"Expected output file not found at {RESULTS_PATH}"
    assert os.path.isfile(RESULTS_PATH), f"Path {RESULTS_PATH} is not a file"
    try:
        with open(RESULTS_PATH, "r") as f:
            actual_data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse JSON from {RESULTS_PATH}: {e}")

    assert isinstance(actual_data, list), "JSON root must be an array"
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} records, found {len(actual_data)}"

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert isinstance(actual, dict), f"Record {i} must be an object"
        assert "node_id" in actual, f"Record {i} missing 'node_id'"
        assert "recorded_at" in actual, f"Record {i} missing 'recorded_at'"
        assert "cumulative_score" in actual, f"Record {i} missing 'cumulative_score'"
        assert set(actual) == {"node_id", "recorded_at", "cumulative_score"}, f"Record {i} has fields outside the required schema"
        assert isinstance(actual["node_id"], str), f"Record {i}: node_id must be a string"
        assert isinstance(actual["recorded_at"], str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", actual["recorded_at"]), f"Record {i}: recorded_at must be YYYY-MM-DD"
        assert isinstance(actual["cumulative_score"], (int, float)) and not isinstance(actual["cumulative_score"], bool), f"Record {i}: cumulative_score must be numeric"
        assert actual["node_id"] == expected["node_id"], f"Record {i}: Expected node_id '{expected['node_id']}', got '{actual['node_id']}'"
        assert actual["recorded_at"] == expected["recorded_at"], f"Record {i}: Expected recorded_at '{expected['recorded_at']}', got '{actual['recorded_at']}'"
        assert float(actual["cumulative_score"]) == expected["cumulative_score"], f"Record {i}: Expected cumulative_score {expected['cumulative_score']}, got {actual['cumulative_score']}"


def test_complete_go_implementation():
    inspect_go_source()
    compile_submission()
    for case_number in (1, 2):
        expected = make_case(case_number)
        run_submission()
        assert_results(expected)
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
