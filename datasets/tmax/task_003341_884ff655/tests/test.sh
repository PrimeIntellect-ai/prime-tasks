#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import subprocess


def test_parquet_file_exists():
    """Check that the output Parquet file exists at the correct absolute path."""
    expected_path = "/home/user/output/verified_reviews.parquet"
    assert os.path.isfile(expected_path), f"Output file {expected_path} is missing."


def test_parquet_contents_and_logic():
    """Recompute the required join and transformations from both source files."""
    script = r'''
import csv
import json
import sys

try:
    import pandas as pd
    from pandas.api.types import is_bool_dtype, is_datetime64_any_dtype
except ImportError:
    sys.stderr.write("pandas is not installed in the environment.\n")
    sys.exit(1)

reviews_path = "/home/user/data/reviews.csv"
logs_path = "/home/user/data/server_logs.jsonl"
file_path = "/home/user/output/verified_reviews.parquet"

try:
    with open(reviews_path, "r", encoding="utf-8", newline="") as handle:
        reviews = list(csv.DictReader(handle))
except Exception as exc:
    sys.stderr.write(f"Failed to parse reviews CSV: {exc}\n")
    sys.exit(1)

try:
    with open(logs_path, "r", encoding="utf-8") as handle:
        logs = [json.loads(line) for line in handle if line.strip()]
except Exception as exc:
    sys.stderr.write(f"Failed to parse server logs: {exc}\n")
    sys.exit(1)

try:
    df = pd.read_parquet(file_path)
except Exception as exc:
    sys.stderr.write(f"Failed to read parquet file: {exc}\n")
    sys.exit(1)

# Preserve the original row-count and required-column assertions.
if len(df) != 4:
    sys.stderr.write(f"Expected exactly 4 rows, got {len(df)}.\n")
    sys.exit(1)

required_columns = {
    "review_id", "user_id", "submitted_at", "review_text",
    "ingest_epoch", "server_ip", "is_verified"
}
missing = required_columns - set(df.columns)
if missing:
    sys.stderr.write(f"Missing required columns: {missing}\n")
    sys.exit(1)

# Enforce the requested output types before comparing values.
for column in ("review_id", "user_id", "review_text", "server_ip"):
    if df[column].isna().any() or not df[column].map(lambda value: isinstance(value, str)).all():
        sys.stderr.write(f"Column {column} must contain non-null strings.\n")
        sys.exit(1)
for column in ("submitted_at", "ingest_epoch"):
    if not is_datetime64_any_dtype(df[column].dtype):
        sys.stderr.write(f"Column {column} must have a timestamp dtype, got {df[column].dtype}.\n")
        sys.exit(1)
if not is_bool_dtype(df["is_verified"].dtype) or df["is_verified"].isna().any():
    sys.stderr.write("Column is_verified must have a non-null boolean dtype.\n")
    sys.exit(1)

if df["review_id"].duplicated().any():
    sys.stderr.write("Output contains duplicate review_id values.\n")
    sys.exit(1)

df = df.set_index("review_id")

# Preserve the original fixed assertions as additional checks.
expected_verification = {
    "R001": True,
    "R002": False,
    "R003": True,
    "R004": True,
}
for rid, expected_val in expected_verification.items():
    if rid not in df.index:
        sys.stderr.write(f"Missing expected review {rid}.\n")
        sys.exit(1)
    actual_val = bool(df.loc[rid, "is_verified"])
    if actual_val != expected_val:
        sys.stderr.write(
            f"Review {rid} 'is_verified' should be {expected_val}, got {actual_val}.\n"
        )
        sys.exit(1)

if "Will never buy again.\nEver." not in df.loc["R002", "review_text"]:
    sys.stderr.write("Embedded newlines were not parsed correctly for R002.\n")
    sys.exit(1)

# Independently derive the inner join and every transformed value from the inputs.
expected_rows = []
for review in reviews:
    rid = review.get("review_id")
    for log in logs:
        if log.get("review_id") == rid:
            try:
                submitted = pd.to_datetime(
                    review["submitted_at"], format="%Y-%m-%d %H:%M:%S", utc=True
                )
                ingest = pd.to_datetime(log["ingest_epoch"], unit="s", utc=True)
            except Exception as exc:
                sys.stderr.write(f"Invalid source timestamp for {rid}: {exc}\n")
                sys.exit(1)
            expected_rows.append({
                "review_id": rid,
                "user_id": review["user_id"],
                "submitted_at": submitted,
                "review_text": review["review_text"],
                "ingest_epoch": ingest,
                "server_ip": log["server_ip"],
                "is_verified": abs((submitted - ingest).total_seconds()) < 10,
            })

expected_ids = [row["review_id"] for row in expected_rows]
if len(expected_ids) != len(set(expected_ids)):
    sys.stderr.write("Source join contains duplicate review IDs and cannot be uniquely validated.\n")
    sys.exit(1)
if len(df) != len(expected_rows) or set(df.index) != set(expected_ids):
    sys.stderr.write(
        "Output review IDs or row count do not match the join derived from the inputs.\n"
    )
    sys.exit(1)

for expected in expected_rows:
    rid = expected["review_id"]
    for column in ("user_id", "review_text", "server_ip"):
        actual = df.loc[rid, column]
        if actual != expected[column]:
            sys.stderr.write(
                f"Review {rid} has incorrect {column}: expected {expected[column]!r}, got {actual!r}.\n"
            )
            sys.exit(1)

    for column in ("submitted_at", "ingest_epoch"):
        actual = pd.to_datetime(df.loc[rid, column], utc=True, errors="coerce")
        if pd.isna(actual) or actual != expected[column]:
            sys.stderr.write(
                f"Review {rid} has incorrect {column}: expected {expected[column]}, got {actual}.\n"
            )
            sys.exit(1)

    actual_verified = bool(df.loc[rid, "is_verified"])
    if actual_verified != expected["is_verified"]:
        sys.stderr.write(
            f"Review {rid} has incorrect derived is_verified: "
            f"expected {expected['is_verified']}, got {actual_verified}.\n"
        )
        sys.exit(1)

sys.exit(0)
'''
    result = subprocess.run(
        [sys.executable, "-c", script],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Parquet validation failed:\n{result.stderr.strip()}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
