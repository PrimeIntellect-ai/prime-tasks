#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

SCRIPT = "/home/user/process_feedback.py"
INPUT_DIR = Path("/home/user/data/input")
OUTPUT_FILE = Path("/home/user/data/output/clean_feedback.jsonl")


def normalize(comment):
    return re.sub(r"\s+", " ", comment).strip().lower()


def read_output():
    assert OUTPUT_FILE.is_file(), f"Output file {OUTPUT_FILE} not found."
    records = []
    with OUTPUT_FILE.open("r", encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                assert False, f"Line {i} is not valid JSON."
    return records


def run_script(check=True):
    return subprocess.run(
        ["runuser", "-u", "user", "--", "/usr/bin/python3", SCRIPT],
        text=True,
        capture_output=True,
        timeout=30,
        check=check,
    )


def test_00_script_executes_and_processes_unseen_inputs():
    """Execute the submitted artifact against fresh CSV and JSON data."""
    assert os.path.isfile(SCRIPT), f"Required Python script {SCRIPT} not found."

    token = secrets.token_hex(12)
    csv_records = [
        {
            "id": "csv-late-" + token,
            "timestamp": "2025-03-02T12:00:00Z",
            "comments": f"  Mixed\n whitespace\t{token}  ",
        },
        {
            "id": "csv-only-" + token,
            "timestamp": "2025-03-01T08:00:00Z",
            "comments": f"Comma, embedded\nline {token}",
        },
    ]
    json_records = [
        {
            "id": "json-early-" + token,
            "timestamp": "2025-03-01T01:00:00Z",
            "comments": f"mixed whitespace {token}",
        },
        {
            "id": "json-only-" + token,
            "timestamp": "2025-03-03T09:30:00Z",
            "comments": f"\tAnother   unique {token}\n",
        },
    ]
    all_records = csv_records + json_records

    expected = {}
    for rec in all_records:
        norm = normalize(rec["comments"])
        digest = hashlib.sha256(norm.encode("utf-8")).hexdigest()
        candidate = {
            "hash": digest,
            "id": rec["id"],
            "timestamp": rec["timestamp"],
            "normalized_comment": norm,
        }
        if digest not in expected or rec["timestamp"] < expected[digest]["timestamp"]:
            expected[digest] = candidate

    with tempfile.TemporaryDirectory() as backup_root:
        backup = Path(backup_root) / "input"
        shutil.copytree(INPUT_DIR, backup)
        try:
            shutil.rmtree(INPUT_DIR)
            INPUT_DIR.mkdir(parents=True, mode=0o777)
            os.chmod(INPUT_DIR, 0o777)

            with (INPUT_DIR / "unseen.csv").open("w", encoding="utf-8", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=["id", "timestamp", "comments"])
                writer.writeheader()
                writer.writerows(csv_records)
            with (INPUT_DIR / "unseen.json").open("w", encoding="utf-8") as f:
                json.dump(json_records, f)
            for path in INPUT_DIR.iterdir():
                os.chmod(path, 0o644)

            if OUTPUT_FILE.exists():
                OUTPUT_FILE.unlink()
            result = run_script(check=False)
            assert result.returncode == 0, (
                f"Submitted script failed on valid CSV/JSON inputs.\n"
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
            )

            records = read_output()
            assert len(records) == len(expected), (
                f"Expected {len(expected)} deduplicated records, got {len(records)}."
            )
            found = {}
            for rec in records:
                assert set(rec.keys()) == {"hash", "id", "timestamp", "normalized_comment"}, (
                    "Each output object must contain exactly hash, id, timestamp, and normalized_comment."
                )
                assert rec["hash"] not in found, "Duplicate hash remained in output."
                found[rec["hash"]] = rec
            assert found == expected, "Output did not correctly normalize, hash, and deduplicate unseen inputs."
        finally:
            shutil.rmtree(INPUT_DIR, ignore_errors=True)
            shutil.copytree(backup, INPUT_DIR)
            if OUTPUT_FILE.exists():
                OUTPUT_FILE.unlink()
            run_script(check=False)


def test_output_file_exists_and_format():
    """Verify that the output file exists and is a valid JSON Lines file."""
    output_file = "/home/user/data/output/clean_feedback.jsonl"
    assert os.path.isfile(output_file), f"Output file {output_file} not found."

    with open(output_file, "r") as f:
        lines = f.readlines()

    assert len(lines) == 3, f"Expected 3 records in the output file, but got {len(lines)}."

    for i, line in enumerate(lines):
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            assert False, f"Line {i+1} is not valid JSON."

        assert "hash" in record, f"Missing 'hash' key in record {i+1}"
        assert "id" in record, f"Missing 'id' key in record {i+1}"
        assert "timestamp" in record, f"Missing 'timestamp' key in record {i+1}"
        assert "normalized_comment" in record, f"Missing 'normalized_comment' key in record {i+1}"
        assert set(record.keys()) == {"hash", "id", "timestamp", "normalized_comment"}, (
            f"Record {i+1} contains keys other than the four required keys."
        )


def test_deduplication_and_hashing():
    """Verify that the records are correctly deduplicated, hashed, and earliest timestamp is kept."""
    output_file = "/home/user/data/output/clean_feedback.jsonl"
    if not os.path.isfile(output_file):
        return

    records = []
    with open(output_file, "r") as f:
        for line in f:
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                pass

    comments = [
        "this is a great product!",
        "terrible, would not buy again.",
        "needs improvement."
    ]
    expected_hashes = {hashlib.sha256(c.encode("utf-8")).hexdigest() for c in comments}

    expected_mapping = {
        hashlib.sha256("this is a great product!".encode("utf-8")).hexdigest(): 201,
        hashlib.sha256("terrible, would not buy again.".encode("utf-8")).hexdigest(): 102,
        hashlib.sha256("needs improvement.".encode("utf-8")).hexdigest(): 202
    }
    expected_timestamps = {
        hashlib.sha256("this is a great product!".encode("utf-8")).hexdigest(): "2023-10-01T09:00:00Z",
        hashlib.sha256("terrible, would not buy again.".encode("utf-8")).hexdigest(): "2023-10-01T10:05:00Z",
        hashlib.sha256("needs improvement.".encode("utf-8")).hexdigest(): "2023-10-01T11:00:00Z",
    }
    expected_comments = {hashlib.sha256(c.encode("utf-8")).hexdigest(): c for c in comments}

    found_hashes = set()
    for rec in records:
        h = rec.get("hash")
        found_hashes.add(h)
        assert h in expected_mapping, f"Unexpected hash found: {h} (normalized comment: {rec.get('normalized_comment')})"

        expected_id = expected_mapping[h]
        actual_id = int(rec.get("id"))
        assert actual_id == expected_id, f"For hash {h}, expected ID {expected_id} (earliest timestamp), got {actual_id}."
        assert rec.get("timestamp") == expected_timestamps[h], f"Incorrect timestamp for hash {h}."
        assert rec.get("normalized_comment") == expected_comments[h], f"Incorrect normalized comment for hash {h}."

        norm_comment = rec.get("normalized_comment")
        calc_hash = hashlib.sha256(norm_comment.encode("utf-8")).hexdigest()
        assert calc_hash == h, f"Hash {h} does not match SHA-256 of normalized comment '{norm_comment}'"

    assert found_hashes == expected_hashes, "Output is missing one or more expected unique feedback hashes."


def test_cron_job_scheduled():
    """Verify that the exact requested cron command is scheduled at 02:00 AM."""
    try:
        cron_out = subprocess.check_output(["crontab", "-l", "-u", "user"], text=True)
    except subprocess.CalledProcessError:
        assert False, "Failed to read crontab for user 'user'."

    lines = cron_out.strip().split("\n")
    found_job = False
    exact_job = False
    for line in lines:
        if line.startswith("#") or not line.strip():
            continue
        if "0 2 * * *" in line or "00 2 * * *" in line:
            if "process_feedback.py" in line:
                found_job = True

        fields = line.split(None, 5)
        if len(fields) == 6:
            minute, hour, dom, month, dow, command = fields
            if (minute in {"0", "00"} and hour == "2" and dom == "*" and
                    month == "*" and dow == "*" and
                    command.strip() == "/usr/bin/python3 /home/user/process_feedback.py"):
                exact_job = True

    assert found_job, "Cron job for process_feedback.py at 02:00 AM not found in crontab."
    assert exact_job, "Cron entry must use the exact requested schedule and command."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
