#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile
from datetime import datetime, timedelta, timezone

import pytest

AGENT_SCRIPT = "/home/user/detector.sh"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"


def test_detector_script_exists_and_executable():
    assert os.path.exists(AGENT_SCRIPT), f"Missing agent script at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"{AGENT_SCRIPT} is not executable"


def run_detector(filepath):
    try:
        result = subprocess.run(
            [AGENT_SCRIPT, filepath],
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as e:
        return f"ERROR: {e}"


def test_evil_corpus_rejected():
    assert os.path.exists(EVIL_CORPUS_DIR) and os.path.isdir(EVIL_CORPUS_DIR), f"Missing evil corpus at {EVIL_CORPUS_DIR}"

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.jsonl')]
    assert len(evil_files) > 0, "No JSONL files found in evil corpus"

    bypassed = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        output = run_detector(filepath)
        if output != "EVIL":
            bypassed.append((filename, output))

    if bypassed:
        details = ", ".join([f"{f} (output: {out})" for f, out in bypassed[:5]])
        if len(bypassed) > 5:
            details += f" ... and {len(bypassed) - 5} more"
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil files bypassed detection. Examples: {details}")


def test_clean_corpus_accepted():
    assert os.path.exists(CLEAN_CORPUS_DIR) and os.path.isdir(CLEAN_CORPUS_DIR), f"Missing clean corpus at {CLEAN_CORPUS_DIR}"

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.jsonl')]
    assert len(clean_files) > 0, "No JSONL files found in clean corpus"

    modified = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        output = run_detector(filepath)
        if output != "CLEAN":
            modified.append((filename, output))

    if modified:
        details = ", ".join([f"{f} (output: {out})" for f, out in modified[:5]])
        if len(modified) > 5:
            details += f" ... and {len(modified) - 5} more"
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean files were incorrectly flagged/modified. Examples: {details}")


def record(host, when, message="ok", metric=1.0):
    return {
        "host_id": host,
        "timestamp": when.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "message": message,
        "metric": metric,
    }


def test_generated_unseen_mixed_cases():
    rng = random.SystemRandom()
    base = datetime(2024, 1, 10, 8, 0, 0, tzinfo=timezone.utc)
    cases = []

    # Random clean files with interleaved hosts, exact-boundary nulls, and
    # unrestricted gaps before non-null metrics.
    for _ in range(12):
        hosts = ["host_" + secrets.token_hex(4) for _ in range(rng.randint(2, 5))]
        current = {h: base + timedelta(seconds=rng.randint(0, 300)) for h in hosts}
        rows = []
        for _ in range(rng.randint(8, 18)):
            host = rng.choice(hosts)
            is_null = rng.random() < 0.45
            delta = rng.randint(0, 3600) if is_null else rng.randint(0, 9000)
            current[host] += timedelta(seconds=delta)
            rows.append(record(host, current[host], metric=None if is_null else rng.random() * 100))
        cases.append((rows, "CLEAN"))

    # Backward time for one host, including unrelated interleaved records.
    for _ in range(10):
        bad_host = "host_" + secrets.token_hex(4)
        other = "host_" + secrets.token_hex(4)
        offset = rng.randint(1000, 5000)
        rows = [
            record(bad_host, base + timedelta(seconds=offset)),
            record(other, base + timedelta(seconds=offset + rng.randint(1, 5000))),
            record(bad_host, base + timedelta(seconds=offset - rng.randint(1, 999))),
        ]
        cases.append((rows, "EVIL"))

    # A null metric more than one hour after the previous record for its host.
    for _ in range(10):
        host = "host_" + secrets.token_hex(4)
        gap = rng.randint(3601, 20000)
        rows = [
            record(host, base, metric=rng.random()),
            record("host_" + secrets.token_hex(4), base + timedelta(seconds=20)),
            record(host, base + timedelta(seconds=gap), metric=None),
        ]
        cases.append((rows, "EVIL"))

    # Unpaired high surrogates are anomalous.
    for _ in range(8):
        host = "host_" + secrets.token_hex(4)
        rows = [record(host, base, message="prefix \ud83d suffix")]
        cases.append((rows, "EVIL"))

    # Paired surrogates and isolated low surrogates do not trigger the legacy
    # high-surrogate check. Include the exact one-hour imputation boundary.
    for i in range(8):
        host = "host_" + secrets.token_hex(4)
        message = "paired 😀 value" if i % 2 == 0 else "low \ude00 value"
        rows = [
            record(host, base, message=message),
            record(host, base + timedelta(seconds=3600), message=message, metric=None),
        ]
        cases.append((rows, "CLEAN"))

    rng.shuffle(cases)
    case_dir = tempfile.mkdtemp(prefix="validation_" + secrets.token_hex(8) + "_")
    created = []
    try:
        for rows, expected in cases:
            path = os.path.join(case_dir, secrets.token_hex(16) + ".jsonl")
            with open(path, "w", encoding="ascii") as f:
                for row in rows:
                    f.write(json.dumps(row, ensure_ascii=True) + "\n")
            created.append((path, expected))

        # The final detector must classify independently rather than invoking
        # the binary that is being retired.
        legacy = "/app/legacy_validator"
        saved_legacy = None
        saved_mode = None
        if os.path.isfile(legacy):
            with open(legacy, "rb") as f:
                saved_legacy = f.read()
            saved_mode = os.stat(legacy).st_mode & 0o7777
            os.unlink(legacy)

        try:
            failures = []
            for path, expected in created:
                output = run_detector(path)
                if output != expected:
                    failures.append((os.path.basename(path), expected, output))
        finally:
            if saved_legacy is not None:
                with open(legacy, "wb") as f:
                    f.write(saved_legacy)
                os.chmod(legacy, saved_mode)

        if failures:
            details = ", ".join(
                f"{name} (expected {expected}, got {actual})"
                for name, expected, actual in failures[:8]
            )
            if len(failures) > 8:
                details += f" ... and {len(failures) - 8} more"
            pytest.fail(f"{len(failures)} generated cases were misclassified: {details}")
    finally:
        shutil.rmtree(case_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
