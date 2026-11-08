#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import re
import secrets
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path

HEADER = ["transaction_id", "user_id", "timestamp", "comments"]
PATTERN = re.compile(r"PROJ-XRAY-\d{4}-ZULU")
MANIFEST = "/home/user/filter_project/Cargo.toml"


def parse_iso8601(ts):
    try:
        if ts.endswith("Z"):
            ts = ts[:-1] + "+00:00"
        return datetime.fromisoformat(ts)
    except ValueError:
        return ts


def get_expected_output(csv_path):
    with open(csv_path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == HEADER
        rows = list(reader)

    user_groups = {}
    for row in rows:
        user_groups.setdefault(row["user_id"], []).append(row)

    expected_rows = []
    for uid, group in user_groups.items():
        group.sort(key=lambda x: parse_iso8601(x["timestamp"]))
        first_record = dict(group[0])
        if PATTERN.search(first_record["comments"]):
            continue
        first_record["comments"] = first_record["comments"].strip()
        expected_rows.append(first_record)

    return expected_rows


def run_rust_tool(csv_path):
    assert os.path.isfile(MANIFEST), f"Rust project not found at {MANIFEST}"
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", MANIFEST, "--", str(csv_path)],
        capture_output=True,
        text=True,
        timeout=120,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Cargo run failed for {csv_path}:\n{result.stderr}")

    # Output must always be CSV with the required header, including when no rows survive.
    assert result.stdout.strip(), f"No CSV header was printed for {csv_path}"
    reader = csv.DictReader(io.StringIO(result.stdout, newline=""))
    assert reader.fieldnames == HEADER, (
        f"Incorrect or missing output header for {csv_path}: {reader.fieldnames!r}"
    )
    rows = list(reader)
    for row in rows:
        assert None not in row, f"Malformed CSV output for {csv_path}: {row!r}"
        assert set(row.keys()) == set(HEADER), f"Unexpected output columns: {row!r}"
    return rows


def assert_file_result(csv_path):
    expected = get_expected_output(csv_path)
    actual = run_rust_tool(csv_path)
    expected_set = {tuple(row.items()) for row in expected}
    actual_set = {tuple(row.items()) for row in actual}
    assert expected_set == actual_set, (
        f"Incorrect sanitization for {csv_path}: expected {expected!r}, got {actual!r}"
    )


def test_clean_corpus():
    clean_dir = Path("/app/corpora/clean")
    assert clean_dir.exists() and clean_dir.is_dir()
    files = list(clean_dir.glob("*.csv"))
    assert files
    for csv_file in files:
        assert_file_result(csv_file)


def test_evil_corpus():
    evil_dir = Path("/app/corpora/evil")
    assert evil_dir.exists() and evil_dir.is_dir()
    files = list(evil_dir.glob("*.csv"))
    assert files
    for csv_file in files:
        assert_file_result(csv_file)


def write_csv(path, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=HEADER, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def test_runtime_generated_corpora():
    token = secrets.token_hex(8)
    u1, u2, u3, u4, u5 = [f"user-{token}-{i}" for i in range(5)]
    sensitive_a = f"PROJ-XRAY-{secrets.randbelow(10000):04d}-ZULU"
    sensitive_b = f"PROJ-XRAY-{secrets.randbelow(10000):04d}-ZULU"

    with tempfile.TemporaryDirectory(prefix=f"csv-verifier-{token}-") as td:
        td = Path(td)

        mixed = td / f"mixed-{secrets.token_hex(6)}.csv"
        write_csv(mixed, [
            {"transaction_id": f"tx-{token}-later", "user_id": u1,
             "timestamp": "2025-06-03T12:00:00Z", "comments": "later record"},
            {"transaction_id": f"tx-{token}-early", "user_id": u1,
             "timestamp": "2024-01-02T03:04:05Z", "comments": "  earliest, quoted value  "},
            {"transaction_id": f"tx-{token}-safe", "user_id": u2,
             "timestamp": "2023-02-01T00:00:00Z", "comments": f" safe {token} "},
            {"transaction_id": f"tx-{token}-badlater", "user_id": u2,
             "timestamp": "2026-02-01T00:00:00Z", "comments": f"contains {sensitive_a} later"},
            {"transaction_id": f"tx-{token}-badfirst", "user_id": u3,
             "timestamp": "2022-01-01T00:00:00Z", "comments": f"prefix {sensitive_b} suffix"},
            {"transaction_id": f"tx-{token}-goodlater", "user_id": u3,
             "timestamp": "2027-01-01T00:00:00Z", "comments": "must not replace filtered first row"},
            {"transaction_id": f"tx-{token}-near", "user_id": u4,
             "timestamp": "2021-09-09T09:09:09Z", "comments": "  PROJ-XRAY-123-ZULU is not the pattern  "},
            {"transaction_id": f"tx-{token}-csv", "user_id": u5,
             "timestamp": "2020-08-08T08:08:08Z", "comments": f"  comma, quote \" and {token}  "},
        ])
        assert_file_result(mixed)

        all_sensitive = td / f"all-sensitive-{secrets.token_hex(6)}.csv"
        write_csv(all_sensitive, [
            {"transaction_id": f"bad-{token}-1", "user_id": f"bad-user-{token}-1",
             "timestamp": "2020-01-01T00:00:00Z", "comments": f"{sensitive_a}"},
            {"transaction_id": f"bad-{token}-2", "user_id": f"bad-user-{token}-2",
             "timestamp": "2020-01-02T00:00:00Z", "comments": f" before {sensitive_b} after "},
        ])
        expected = get_expected_output(all_sensitive)
        assert expected == []
        actual = run_rust_tool(all_sensitive)
        assert actual == [], f"Sensitive rows were not removed: {actual!r}"


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
