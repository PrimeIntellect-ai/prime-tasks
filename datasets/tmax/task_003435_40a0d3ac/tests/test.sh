#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import string
import subprocess
import tempfile

import pytest

ETL = "/home/user/etl.go"
ROLLSTAT_DIR = "/app/vendored/go-rollstat"


def test_makefile_fixed():
    makefile_path = os.path.join(ROLLSTAT_DIR, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile not found at {makefile_path}"

    with open(makefile_path, "r") as f:
        content = f.read()

    assert "-tags=production" in content, "Makefile was not fixed to use '-tags=production'"
    assert not re.search(r"-tags=prod(?:\\s|$)", content), "Makefile still contains the faulty '-tags=prod'"


def test_vendored_package_actually_builds():
    result = subprocess.run(
        ["make", "-C", ROLLSTAT_DIR], capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, (
        "The vendored package does not build through its repaired Makefile:\n"
        + result.stdout + result.stderr
    )


def test_etl_imports_and_uses_rollstat_window():
    assert os.path.isfile(ETL), f"ETL script not found at {ETL}"
    checker = r'''
package main

import (
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "path"
    "strconv"
)

func main() {
    f, err := parser.ParseFile(token.NewFileSet(), "/home/user/etl.go", nil, 0)
    if err != nil { os.Exit(2) }

    aliases := map[string]bool{}
    for _, imp := range f.Imports {
        p, err := strconv.Unquote(imp.Path.Value)
        if err != nil || p != "github.com/fake/go-rollstat" { continue }
        name := path.Base(p)
        if imp.Name != nil { name = imp.Name.Name }
        if name != "_" && name != "." { aliases[name] = true }
    }
    if len(aliases) == 0 { os.Exit(3) }

    used := false
    ast.Inspect(f, func(n ast.Node) bool {
        s, ok := n.(*ast.SelectorExpr)
        if !ok || s.Sel.Name != "Window" { return true }
        id, ok := s.X.(*ast.Ident)
        if ok && aliases[id.Name] { used = true }
        return true
    })
    if !used { os.Exit(4) }
}
'''
    with tempfile.TemporaryDirectory() as d:
        checker_path = os.path.join(d, "check.go")
        with open(checker_path, "w") as f:
            f.write(checker)
        result = subprocess.run(
            ["go", "run", checker_path], capture_output=True, text=True, timeout=60
        )
    assert result.returncode == 0, (
        "/home/user/etl.go must import github.com/fake/go-rollstat and use its Window type"
    )


def is_valid_record(record):
    if not isinstance(record, dict):
        return False
    ts = record.get("ts")
    val = record.get("val")
    ident = record.get("id")
    if isinstance(ts, bool) or not isinstance(ts, int) or ts <= 0:
        return False
    if isinstance(val, bool) or not isinstance(val, (int, float)) or not math.isfinite(val):
        return False
    if not (-100.0 <= val <= 100.0):
        return False
    if not isinstance(ident, str) or re.fullmatch(r"[A-Z0-9]+", ident) is None:
        return False
    return True


def compute_expected_output(input_lines):
    records = []
    for line in input_lines:
        if not line.strip():
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if is_valid_record(rec):
            records.append(rec)

    if not records:
        return []

    # Keep the first valid input record for each timestamp, then sort by timestamp.
    seen_ts = set()
    deduped = []
    for rec in records:
        if rec["ts"] not in seen_ts:
            deduped.append({"ts": rec["ts"], "val": rec["val"], "id": rec["id"]})
            seen_ts.add(rec["ts"])
    deduped.sort(key=lambda x: x["ts"])

    filled = []
    current_idx = 0
    last_valid = None
    for ts in range(deduped[0]["ts"], deduped[-1]["ts"] + 1):
        if current_idx < len(deduped) and deduped[current_idx]["ts"] == ts:
            last_valid = deduped[current_idx]
            current_idx += 1
        rec = last_valid.copy()
        rec["ts"] = ts
        filled.append(rec)

    output = []
    for i, rec in enumerate(filled):
        window = filled[max(0, i - 2):i + 1]
        out = rec.copy()
        out["avg"] = round(sum(item["val"] for item in window) / len(window), 2)
        output.append(out)
    return output


def run_etl(input_path, output_path):
    assert os.path.isfile(ETL), f"ETL script not found at {ETL}"
    result = subprocess.run(
        ["go", "run", ETL, input_path, output_path],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"ETL script failed for {input_path}:\n{result.stderr}"


def read_output_strict(output_path):
    actual = []
    with open(output_path, "r") as f:
        for line_number, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError as exc:
                pytest.fail(f"Output line {line_number} is not valid JSON: {exc}")
            assert isinstance(rec, dict), f"Output line {line_number} is not a JSON object"
            assert set(rec) == {"ts", "val", "id", "avg"}, (
                f"Output line {line_number} must contain exactly ts, val, id, and avg"
            )
            assert isinstance(rec["ts"], int) and not isinstance(rec["ts"], bool)
            assert isinstance(rec["id"], str)
            for key in ("val", "avg"):
                assert isinstance(rec[key], (int, float)) and not isinstance(rec[key], bool)
                assert math.isfinite(rec[key])
            actual.append(rec)
    return actual


def assert_output_matches(input_lines, output_path):
    expected = compute_expected_output(input_lines)
    actual = read_output_strict(output_path)
    assert len(actual) == len(expected), f"Expected {len(expected)} records, got {len(actual)}"
    for index, (got, want) in enumerate(zip(actual, expected)):
        assert got["ts"] == want["ts"], f"Wrong ts at output record {index}"
        assert got["id"] == want["id"], f"Wrong id at output record {index}"
        assert got["val"] == want["val"], f"Wrong val at output record {index}"
        assert got["avg"] == want["avg"], f"Wrong avg at output record {index}"


def test_evil_corpus():
    evil_dir = "/app/data/evil/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} not found"
    files = [f for f in os.listdir(evil_dir) if f.endswith(".jsonl")]
    assert len(files) > 0, "No evil corpus files found"

    bypassed = []
    for file in files:
        input_path = os.path.join(evil_dir, file)
        with tempfile.NamedTemporaryFile(suffix=".jsonl", delete=False) as tmp:
            output_path = tmp.name
        try:
            run_etl(input_path, output_path)
            if read_output_strict(output_path):
                bypassed.append(file)
        finally:
            if os.path.exists(output_path):
                os.remove(output_path)
    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(files)} evil bypassed: {', '.join(bypassed)}")


def test_clean_corpus():
    clean_dir = "/app/data/clean/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} not found"
    files = [f for f in os.listdir(clean_dir) if f.endswith(".jsonl")]
    assert len(files) > 0, "No clean corpus files found"

    modified = []
    for file in files:
        input_path = os.path.join(clean_dir, file)
        with open(input_path, "r") as f:
            input_lines = f.readlines()
        with tempfile.NamedTemporaryFile(suffix=".jsonl", delete=False) as tmp:
            output_path = tmp.name
        try:
            run_etl(input_path, output_path)
            try:
                assert_output_matches(input_lines, output_path)
            except AssertionError:
                modified.append(file)
        finally:
            if os.path.exists(output_path):
                os.remove(output_path)
    if modified:
        pytest.fail(f"{len(modified)} of {len(files)} clean modified or incorrectly processed: {', '.join(modified)}")


def random_id():
    alphabet = string.ascii_uppercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(6))


def make_adversarial_case():
    base = 1000 + secrets.randbelow(500000)
    offsets = [0, 2, 5, 8, 12]
    values = [
        -100,
        secrets.randbelow(181) - 90,
        secrets.randbelow(181) - 90,
        secrets.randbelow(181) - 90,
        100,
    ]
    valid = [
        {"ts": base + off, "val": val, "id": random_id()}
        for off, val in zip(offsets, values)
    ]

    # Exact duplicate and conflicting records at existing timestamps. Input order,
    # not value or id, decides which conflicting record survives.
    records = valid + [valid[1].copy()]
    records += [
        {"ts": base + 5, "val": secrets.randbelow(181) - 90, "id": random_id()},
        {"ts": base + 8, "val": secrets.randbelow(181) - 90, "id": random_id()},
    ]
    records += [
        {"ts": 0, "val": 10, "id": random_id()},
        {"ts": -1 - secrets.randbelow(100), "val": 10, "id": random_id()},
        {"ts": base + 3, "val": 100.01, "id": random_id()},
        {"ts": base + 4, "val": -100.01, "id": random_id()},
        {"ts": base + 6, "val": 10, "id": "bad" + random_id()},
        {"ts": base + 7, "val": 10, "id": random_id() + "_"},
        {"ts": base + 9, "val": 10, "id": ""},
    ]
    random.SystemRandom().shuffle(records)
    return [json.dumps(rec) + "\n" for rec in records]


def test_runtime_generated_adversarial_datasets():
    for _ in range(4):
        input_lines = make_adversarial_case()
        with tempfile.NamedTemporaryFile(mode="w", suffix=".jsonl", delete=False) as inp:
            inp.writelines(input_lines)
            input_path = inp.name
        with tempfile.NamedTemporaryFile(suffix=".jsonl", delete=False) as out:
            output_path = out.name
        try:
            run_etl(input_path, output_path)
            assert_output_matches(input_lines, output_path)
        finally:
            os.remove(input_path)
            if os.path.exists(output_path):
                os.remove(output_path)


def test_runtime_generated_all_invalid_dataset():
    base = 1000 + secrets.randbelow(500000)
    records = [
        {"ts": -base, "val": 0, "id": random_id()},
        {"ts": base, "val": 101 + secrets.randbelow(100), "id": random_id()},
        {"ts": base + 1, "val": -101 - secrets.randbelow(100), "id": random_id()},
        {"ts": base + 2, "val": 0, "id": "lower" + random_id()},
        {"ts": base + 3, "val": 0, "id": random_id() + "!"},
    ]
    input_lines = [json.dumps(rec) + "\n" for rec in records]
    with tempfile.NamedTemporaryFile(mode="w", suffix=".jsonl", delete=False) as inp:
        inp.writelines(input_lines)
        input_path = inp.name
    with tempfile.NamedTemporaryFile(suffix=".jsonl", delete=False) as out:
        output_path = out.name
    try:
        run_etl(input_path, output_path)
        assert_output_matches(input_lines, output_path)
    finally:
        os.remove(input_path)
        if os.path.exists(output_path):
            os.remove(output_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
