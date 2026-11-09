#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import csv
import io
import os
import random
import re
import secrets
import subprocess
import tempfile

import pytest

PROGRAM = "/home/user/filter_data.go"
HOME = "/home/user"
METADATA = "/app/data/metadata.csv"
PACKAGE = "/app/vendor/tabular"


def run(cmd, cwd=None, timeout=60):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def parse_csv_output(stdout):
    if not stdout.strip():
        return [], []
    try:
        records = list(csv.reader(io.StringIO(stdout)))
    except csv.Error as exc:
        pytest.fail(f"Output is not valid CSV: {exc}")
    assert records, "CSV output unexpectedly contained no records"
    width = len(records[0])
    assert width > 0, "CSV header is empty"
    assert all(len(row) == width for row in records), "CSV output has inconsistent row widths"
    return records[0], records[1:]


def assert_joined_rows(stdout, expected):
    header, rows = parse_csv_output(stdout)
    assert header, "Expected a CSV header"
    assert len(header) == len(set(header)), "CSV header contains duplicate columns"
    assert "user_id" in header, "Output is missing user_id"
    assert "risk_score" in header, "Output is missing risk_score"
    uid_idx = header.index("user_id")
    risk_idx = header.index("risk_score")

    actual = {}
    for row in rows:
        uid = row[uid_idx]
        assert uid not in actual, f"Duplicate output row for user_id {uid}"
        try:
            score = float(row[risk_idx])
        except ValueError:
            pytest.fail(f"Non-numeric risk_score for user_id {uid}: {row[risk_idx]!r}")
        actual[uid] = score

    assert set(actual) == set(expected), f"Expected user IDs {set(expected)}, got {set(actual)}"
    for uid, score in expected.items():
        assert actual[uid] == pytest.approx(score), (
            f"Wrong joined risk_score for user_id {uid}: expected {score}, got {actual[uid]}"
        )


@contextlib.contextmanager
def replaced_metadata(rows):
    with open(METADATA, "rb") as f:
        original = f.read()
    try:
        with open(METADATA, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["user_id", "risk_score"])
            writer.writerows(rows)
        yield
    finally:
        with open(METADATA, "wb") as f:
            f.write(original)


def write_csv(path, header, rows):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)


def test_config_perturbation_fixed():
    config_path = "/app/vendor/tabular/config.go"
    assert os.path.isfile(config_path), f"Vendored package file {config_path} is missing."
    with open(config_path, "r") as f:
        content = f.read()
    assert "DisableImputation = true" not in content, "The perturbation in config.go was not fixed. DisableImputation is still true."


def test_go_program_exists():
    assert os.path.isfile(PROGRAM), "/home/user/filter_data.go is missing."


def test_module_uses_replaced_vendored_package():
    mod_path = os.path.join(HOME, "go.mod")
    assert os.path.isfile(mod_path), "/home/user/go.mod is missing."
    with open(mod_path) as f:
        mod = f.read()
    assert re.search(
        r"(?m)^\s*replace\s+github\.com/data-prep/tabular(?:\s+v\S+)?\s*=>\s*/app/vendor/tabular\s*$",
        mod,
    ), "go.mod does not replace github.com/data-prep/tabular with /app/vendor/tabular"

    result = run(["go", "list", "-deps", "."], cwd=HOME)
    assert result.returncode == 0, f"Go program does not compile:\n{result.stderr}"
    assert "github.com/data-prep/tabular" in result.stdout.splitlines(), (
        "The program does not import github.com/data-prep/tabular"
    )


def test_vendored_package_really_joins_and_keeps_missing_rows():
    token = secrets.randbelow(800000) + 100000
    uid_a = str(token)
    uid_b = str(token + 1)
    uid_unknown = str(token + 99)
    score_a = round(random.uniform(3.0, 40.0), 4)
    score_b = round(random.uniform(60.0, 97.0), 4)

    with tempfile.TemporaryDirectory(prefix="tabular_behavior_") as td:
        input_path = os.path.join(td, secrets.token_hex(8) + ".csv")
        metadata_path = os.path.join(td, secrets.token_hex(8) + ".csv")
        write_csv(input_path, ["user_id", "val"], [
            [uid_a, ""],
            [uid_b, "present"],
            [uid_unknown, "not-joinable"],
        ])
        write_csv(metadata_path, ["user_id", "risk_score"], [
            [uid_a, score_a],
            [uid_b, score_b],
        ])

        with open(os.path.join(td, "go.mod"), "w") as f:
            f.write("module verifier/packagecheck\n\ngo 1.18\n\n")
            f.write("require github.com/data-prep/tabular v0.0.0\n")
            f.write("replace github.com/data-prep/tabular => /app/vendor/tabular\n")
        with open(os.path.join(td, "main.go"), "w") as f:
            f.write(r'''package main
import (
    "encoding/csv"
    "fmt"
    "os"
    tabular "github.com/data-prep/tabular"
)
func main() {
    if len(os.Args) != 3 { panic("expected input and metadata") }
    rows, err := tabular.JoinAndImpute(os.Args[1], os.Args[2])
    if err != nil { panic(err) }
    w := csv.NewWriter(os.Stdout)
    for _, row := range rows {
        if err := w.Write(row); err != nil { panic(err) }
    }
    w.Flush()
    if err := w.Error(); err != nil { panic(err) }
    fmt.Fprint(os.Stderr, "")
}
''')
        result = run(["go", "run", ".", input_path, metadata_path], cwd=td)
        assert result.returncode == 0, (
            "Vendored tabular package failed to compile or execute JoinAndImpute:\n"
            + result.stderr
        )
        assert_joined_rows(result.stdout, {uid_a: score_a, uid_b: score_b})


def test_program_on_generated_join_and_filter_cases():
    # Randomized IDs, scores, and filenames prevent solutions tailored to the shipped corpus.
    for _ in range(2):
        base = secrets.randbelow(7000000) + 1000000
        valid_a = str(base)
        valid_b = str(base + 1)
        low_boundary = str(base + 2)
        high_boundary = str(base + 3)
        high_outlier = str(base + 4)
        low_outlier = str(base + 5)
        unknown = str(base + 777)
        score_a = round(random.uniform(1.0, 45.0), 5)
        score_b = round(random.uniform(55.0, 99.0), 5)

        metadata_rows = [
            [valid_a, score_a],
            [valid_b, score_b],
            [low_boundary, 0.0],
            [high_boundary, 100.0],
            [high_outlier, 100.001],
            [low_outlier, -0.001],
        ]

        with tempfile.TemporaryDirectory(prefix="pipeline_case_") as td:
            input_path = os.path.join(td, secrets.token_hex(12) + ".csv")
            write_csv(input_path, ["user_id", "val"], [
                [valid_a, "alpha"],
                [valid_b, ""],  # A missing value must not cause this joinable row to be dropped.
                [low_boundary, "zero"],
                [high_boundary, "hundred"],
                [high_outlier, "bad-high"],
                [low_outlier, "bad-low"],
                [unknown, "unjoinable"],
            ])

            with replaced_metadata(metadata_rows):
                result = run(["go", "run", "filter_data.go", input_path], cwd=HOME)

            assert result.returncode == 0, f"Program crashed on valid CSV input:\n{result.stderr}"
            assert_joined_rows(result.stdout, {
                valid_a: score_a,
                valid_b: score_b,
                low_boundary: 0.0,
                high_boundary: 100.0,
            })


def test_program_generated_all_rejected_case_exits_successfully():
    base = secrets.randbelow(7000000) + 1000000
    high = str(base)
    low = str(base + 1)
    unknown = str(base + 99)
    with tempfile.TemporaryDirectory(prefix="pipeline_reject_") as td:
        input_path = os.path.join(td, secrets.token_hex(12) + ".csv")
        write_csv(input_path, ["user_id", "val"], [
            [high, "x"], [low, "y"], [unknown, "z"],
        ])
        with replaced_metadata([[high, 150.0], [low, -20.0]]):
            result = run(["go", "run", "filter_data.go", input_path], cwd=HOME)

    assert result.returncode == 0, f"Program crashed instead of gracefully rejecting rows:\n{result.stderr}"
    header, rows = parse_csv_output(result.stdout)
    assert len(rows) == 0, f"Expected zero data rows, got {rows}"


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.csv')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.csv')]

    assert len(clean_files) > 0, "No clean CSV files found."
    assert len(evil_files) > 0, "No evil CSV files found."

    clean_failures = []
    for cf in clean_files:
        result = run(["go", "run", "filter_data.go", cf], cwd=HOME)
        if result.returncode != 0:
            clean_failures.append(f"{os.path.basename(cf)} (Execution failed: {result.stderr.strip()})")
            continue
        lines = [line for line in result.stdout.strip().split('\n') if line.strip()]
        if len(lines) <= 1:
            clean_failures.append(f"{os.path.basename(cf)} (Produced {len(lines)} lines, expected > 1)")

    evil_failures = []
    for ef in evil_files:
        result = run(["go", "run", "filter_data.go", ef], cwd=HOME)
        if result.returncode != 0:
            evil_failures.append(f"{os.path.basename(ef)} (Execution failed: {result.stderr.strip()})")
            continue
        lines = [line for line in result.stdout.strip().split('\n') if line.strip()]
        if len(lines) > 1:
            evil_failures.append(f"{os.path.basename(ef)} (Produced {len(lines)} lines, expected <= 1)")

    error_messages = []
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: " + ", ".join(evil_failures))
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/failed: " + ", ".join(clean_failures))
    assert not error_messages, " | ".join(error_messages)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
