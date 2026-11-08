#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import shutil
import string
import subprocess
import tempfile

import pytest


def get_actual_bad_commit(repo_path):
    # Find all commits from v1.0.0 to HEAD
    result = subprocess.run(
        ["git", "rev-list", "v1.0.0..HEAD", "--reverse"],
        cwd=repo_path,
        capture_output=True,
        text=True,
        check=True,
    )
    commits = result.stdout.strip().splitlines()

    for commit in commits:
        # Checkout commit
        subprocess.run(
            ["git", "checkout", commit],
            cwd=repo_path,
            capture_output=True,
            check=False,
        )
        # Run tests
        test_result = subprocess.run(
            ["go", "test", "./..."], cwd=repo_path, capture_output=True
        )
        if test_result.returncode != 0:
            # Restore HEAD
            subprocess.run(
                ["git", "checkout", "main"],
                cwd=repo_path,
                capture_output=True,
                check=False,
            )
            return commit

    # Restore HEAD
    subprocess.run(
        ["git", "checkout", "main"],
        cwd=repo_path,
        capture_output=True,
        check=False,
    )
    return None


def test_report_content_and_commit():
    report_path = "/home/user/report.txt"
    assert os.path.exists(report_path), f"Report file missing at {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    assert len(lines) >= 2, f"Report file must contain at least 2 lines, found {len(lines)}"

    reported_commit = lines[0]
    reported_filter = lines[1]

    assert reported_filter == "/home/user/diag_filter", (
        f"Line 2 of report should be '/home/user/diag_filter', got '{reported_filter}'"
    )

    repo_path = "/home/user/diag_service"
    actual_bad_commit = get_actual_bad_commit(repo_path)
    assert actual_bad_commit is not None, (
        "Could not determine the bad commit in /home/user/diag_service"
    )

    # Check if the reported commit is a prefix or exact match
    assert reported_commit == actual_bad_commit or actual_bad_commit.startswith(reported_commit), \
        f"Incorrect bad commit reported. Expected {actual_bad_commit}, got {reported_commit}"


def run_filter(filter_bin, payload_path):
    try:
        return subprocess.run(
            [filter_bin, payload_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter timed out while processing {payload_path}")


def xor_checksum(data):
    value = 0
    for byte in data.encode("utf-8"):
        value ^= byte
    return f"{value:02x}"


def trunc_div(value, divisor):
    if value >= 0:
        return value // divisor
    return -((-value) // divisor)


def make_generated_cases():
    rng = secrets.SystemRandom()
    alphabet = string.ascii_letters + string.digits + " _-:/" + "éΩ中"
    cases = []

    # Independently derive valid and invalid payloads over values and filenames
    # not present in the image's fixed clean/evil corpus.
    for _ in range(48):
        ts = rng.randint(-2_000_000_000, 2_000_000_000)
        quotient = trunc_div(ts, 3600)
        tz = (-quotient) % 24
        if tz > 14 or (tz > 0 and rng.randrange(2) == 0):
            tz -= 24
        data = "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 80)))
        checksum = xor_checksum(data)
        valid = {
            "unix_ts": ts,
            "tz_offset_hours": tz,
            "data": data,
            "checksum": checksum,
            "ignored_field": rng.randint(0, 100000),
        }
        cases.append((json.dumps(valid, ensure_ascii=False).encode("utf-8"), True))

        bad_checksum = dict(valid)
        bad_checksum["checksum"] = f"{(int(checksum, 16) + 1) & 0xff:02x}"
        cases.append((json.dumps(bad_checksum, ensure_ascii=False).encode("utf-8"), False))

        bad_offset = dict(valid)
        bad_offset["tz_offset_hours"] = tz + 1
        cases.append((json.dumps(bad_offset, ensure_ascii=False).encode("utf-8"), False))

    # Exercise parsing/default behavior as well as malformed and mistyped JSON.
    cases.extend([
        (b'{"unix_ts":0,"tz_offset_hours":0,"data":"","checksum":"00"}', True),
        (b'{"checksum":"00"}', True),
        (b'{}', False),
        (b'', False),
        (b'not json', False),
        (b'{"unix_ts":0,"tz_offset_hours":0,"data":3,"checksum":"00"}', False),
        (b'{"unix_ts":"0","tz_offset_hours":0,"data":"","checksum":"00"}', False),
        (b'{"unix_ts":0,"tz_offset_hours":0,"data":"","checksum":"00"} trailing', False),
    ])
    rng.shuffle(cases)
    return cases


def assert_generated_behavior(filter_bin):
    corpus_dir = tempfile.mkdtemp(prefix="diag_payloads_")
    try:
        failures = []
        for index, (contents, should_accept) in enumerate(make_generated_cases()):
            token = secrets.token_hex(12)
            payload_path = os.path.join(corpus_dir, f"{token}_{index}.json")
            with open(payload_path, "wb") as payload_file:
                payload_file.write(contents)
            returncode = run_filter(filter_bin, payload_path)
            accepted = returncode == 0
            if accepted != should_accept:
                failures.append(
                    f"case {index}: expected {'accept' if should_accept else 'reject'}, "
                    f"got exit code {returncode}"
                )
        assert not failures, "Generated corpus failures: " + " | ".join(failures[:10])
    finally:
        shutil.rmtree(corpus_dir, ignore_errors=True)


def test_diag_filter_adversarial_corpus():
    filter_bin = "/home/user/diag_filter"
    source_path = "/home/user/diag_filter.go"
    oracle_path = "/app/diag_oracle"

    assert os.path.exists(filter_bin), f"Filter binary missing at {filter_bin}"
    assert os.access(filter_bin, os.X_OK), f"Filter binary at {filter_bin} is not executable"
    assert os.path.isfile(source_path), f"Go source missing at {source_path}"

    with open(filter_bin, "rb") as submitted, open(oracle_path, "rb") as oracle:
        assert submitted.read() != oracle.read(), "Submitted filter is byte-identical to diag_oracle"

    build_dir = tempfile.mkdtemp(prefix="diag_filter_build_")
    rebuilt_filter = os.path.join(build_dir, "diag_filter")
    try:
        build = subprocess.run(
            ["go", "build", "-o", rebuilt_filter, source_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        assert build.returncode == 0, (
            "diag_filter.go did not compile: " + build.stderr.decode("utf-8", errors="replace")
        )

        clean_corpus_dir = "/app/corpora/clean"
        evil_corpus_dir = "/app/corpora/evil"

        clean_files = glob.glob(os.path.join(clean_corpus_dir, "*"))
        evil_files = glob.glob(os.path.join(evil_corpus_dir, "*"))

        assert len(clean_files) > 0, "No clean corpus files found to test against"
        assert len(evil_files) > 0, "No evil corpus files found to test against"

        clean_failed = []
        for fpath in clean_files:
            res = subprocess.run([filter_bin, fpath], capture_output=True)
            if res.returncode != 0:
                clean_failed.append(os.path.basename(fpath))

        evil_bypassed = []
        for fpath in evil_files:
            res = subprocess.run([filter_bin, fpath], capture_output=True)
            if res.returncode == 0:
                evil_bypassed.append(os.path.basename(fpath))

        error_msgs = []
        if clean_failed:
            error_msgs.append(
                f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: "
                + ", ".join(clean_failed[:5])
            )
        if evil_bypassed:
            error_msgs.append(
                f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed/accepted: "
                + ", ".join(evil_bypassed[:5])
            )

        if error_msgs:
            pytest.fail(" | ".join(error_msgs))

        # Test both the required artifact and a fresh build of the submitted Go source
        # against dynamically generated, neutrally named payloads.
        assert_generated_behavior(filter_bin)
        assert_generated_behavior(rebuilt_filter)
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
