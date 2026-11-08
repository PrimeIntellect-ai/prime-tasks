#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess
import time
from datetime import datetime, timedelta, timezone

import pymongo
import pytest

BINARY_PATH = "/home/user/backup_analyzer/target/release/backup_analyzer"
REPORT_PATH = "/home/user/report.jsonl"
THRESHOLD = 1.5
EXPECTED = []


@pytest.fixture(scope="session", autouse=True)
def seed_database():
    global EXPECTED

    client = pymongo.MongoClient("mongodb://127.0.0.1:27017/", serverSelectionTimeoutMS=5000)
    client.admin.command("ping")
    db = client.backups

    # Disable profiling while replacing any data left by the agent or image.
    db.command("profile", 0)
    db.jobs.drop()
    db.chunks.drop()
    try:
        db["system.profile"].drop()
    except Exception:
        pass

    prefix = secrets.token_hex(12)
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    jobs = []
    chunks = []
    valid = []

    # Both completion time and total size increase together, so the requested
    # newest ordering and top-largest selection identify the same 500 jobs.
    for i in range(850):
        job_id = f"{prefix}-valid-{i:04d}"
        completion = base + timedelta(minutes=i)
        retention = 400 if i % 4 == 0 else 60
        total = 1_000_000 + i * 10_000 + (i * 37 % 997)
        first = total // 3
        second = total // 5
        third = total - first - second
        jobs.append({
            "job_id": job_id,
            "status": "COMPLETED",
            "retention_days": retention,
            "completion_time": completion,
        })
        chunks.extend([
            {"job_id": job_id, "size_bytes": first},
            {"job_id": job_id, "size_bytes": second},
            {"job_id": job_id, "size_bytes": third},
        ])
        valid.append({
            "job_id": job_id,
            "total_size_bytes": total,
            "completion_date": completion,
            "is_archived": retention > 365,
        })

    # These tempting, newer and larger rows must be removed by the filters.
    for i in range(100):
        job_id = f"{prefix}-failed-{i:04d}"
        jobs.append({
            "job_id": job_id,
            "status": "FAILED",
            "retention_days": 900,
            "completion_time": base + timedelta(days=10, minutes=i),
        })
        chunks.append({"job_id": job_id, "size_bytes": 9_000_000_000 + i})

    for i in range(100):
        job_id = f"{prefix}-short-{i:04d}"
        jobs.append({
            "job_id": job_id,
            "status": "COMPLETED",
            "retention_days": 30,
            "completion_time": base + timedelta(days=20, minutes=i),
        })
        chunks.append({"job_id": job_id, "size_bytes": 10_000_000_000 + i})

    db.jobs.insert_many(jobs)
    db.chunks.insert_many(chunks)
    db.chunks.create_index("job_id")

    EXPECTED = sorted(valid, key=lambda row: row["completion_date"], reverse=True)[:500]

    # Record the command issued by the submitted binary so the verifier can
    # confirm that the required work is performed in a MongoDB aggregation.
    db.command("profile", 2)
    yield
    db.command("profile", 0)
    client.close()


def test_binary_exists():
    """Test that the compiled Rust binary exists and is executable."""
    assert os.path.isfile(BINARY_PATH), f"Rust binary not found at {BINARY_PATH}. Did you compile in release mode?"
    assert os.access(BINARY_PATH, os.X_OK), f"Rust binary at {BINARY_PATH} is not executable."


def _parse_iso8601(value):
    date_str = value.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(date_str)
    except ValueError:
        pytest.fail(f"Invalid completion_date format (expected ISO8601): {value}")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _find_required_pipeline(profiles):
    for profile in profiles:
        pipeline = profile.get("command", {}).get("pipeline")
        if not isinstance(pipeline, list):
            continue

        match_positions = [i for i, stage in enumerate(pipeline) if "$match" in stage]
        lookup_positions = [i for i, stage in enumerate(pipeline) if "$lookup" in stage]
        sort_positions = [i for i, stage in enumerate(pipeline) if "$sort" in stage]
        limit_positions = [i for i, stage in enumerate(pipeline) if stage.get("$limit") == 500]
        if not (match_positions and lookup_positions and sort_positions and limit_positions):
            continue

        text = json.dumps(pipeline, default=str)
        match_text = json.dumps([pipeline[i]["$match"] for i in match_positions], default=str)
        if not all(token in match_text for token in ("COMPLETED", "retention_days", "$gt", "30")):
            continue

        lookup = pipeline[lookup_positions[0]]["$lookup"]
        if not isinstance(lookup, dict) or lookup.get("from") != "chunks":
            continue

        has_desc_completion_sort = False
        for pos in sort_positions:
            spec = pipeline[pos]["$sort"]
            if isinstance(spec, dict) and any("completion" in key and value == -1 for key, value in spec.items()):
                has_desc_completion_sort = True
                break
        if not has_desc_completion_sort:
            continue

        # The chunk sizes must be combined on the database side, not fetched
        # and totaled solely by the client.
        if "size_bytes" not in text or not any(op in text for op in ("$sum", "$reduce")):
            continue

        if not (match_positions[0] < lookup_positions[0] < limit_positions[-1]):
            continue
        return pipeline
    return None


def test_runtime_report_contents_and_aggregation():
    """Execute the binary, validate every result, and inspect its DB pipeline."""
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    start_time = time.time()
    result = subprocess.run([BINARY_PATH], capture_output=True, timeout=5)
    runtime = time.time() - start_time

    assert result.returncode == 0, (
        f"Binary execution failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr.decode(errors='replace')}"
    )
    assert runtime < THRESHOLD, (
        f"Runtime was {runtime:.3f}s, which exceeds the threshold of {THRESHOLD}s. "
        "Make sure you are using MongoDB aggregation pipelines."
    )
    assert os.path.isfile(REPORT_PATH), f"Report file not created at {REPORT_PATH}"

    with open(REPORT_PATH, "r", encoding="utf-8") as report:
        content = report.read().strip()
    if not content:
        pytest.fail(f"Report file {REPORT_PATH} is empty.")

    lines = content.split("\n")
    assert len(lines) == 500, f"Expected exactly 500 lines in the report, but got {len(lines)}."

    for i, (line, expected) in enumerate(zip(lines, EXPECTED), start=1):
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i} is not valid JSON: {line}")

        assert set(record) == {"job_id", "total_size_bytes", "completion_date", "is_archived"}, \
            f"Line {i} does not strictly match the required schema."
        assert isinstance(record["job_id"], str), f"Line {i} has invalid job_id."
        assert isinstance(record["total_size_bytes"], (int, float)) and not isinstance(record["total_size_bytes"], bool), \
            f"Line {i} has invalid total_size_bytes."
        assert math.isfinite(record["total_size_bytes"]), f"Line {i} has a non-finite total_size_bytes."
        assert isinstance(record["completion_date"], str), f"Line {i} has invalid completion_date."
        assert isinstance(record["is_archived"], bool), f"Line {i} has invalid is_archived."

        actual_date = _parse_iso8601(record["completion_date"])
        assert record["job_id"] == expected["job_id"], f"Line {i} has the wrong job or ordering."
        assert record["total_size_bytes"] == expected["total_size_bytes"], f"Line {i} has the wrong joined chunk total."
        assert actual_date == expected["completion_date"], f"Line {i} has the wrong completion date."
        assert record["is_archived"] is expected["is_archived"], f"Line {i} has the wrong archive flag."

    client = pymongo.MongoClient("mongodb://127.0.0.1:27017/")
    profiles = list(client.backups["system.profile"].find({
        "op": "command",
        "command.aggregate": "jobs",
    }))
    client.backups.command("profile", 0)
    client.close()

    pipeline = _find_required_pipeline(profiles)
    assert pipeline is not None, (
        "No jobs aggregation was observed containing the required status/retention match, "
        "chunks lookup, database-side size calculation, descending completion sort, and 500 limit."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
