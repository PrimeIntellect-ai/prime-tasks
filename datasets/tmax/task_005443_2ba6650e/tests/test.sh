#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import subprocess
import tempfile

import pytest
import requests

REPO = "/home/user/telemetry_svc"
URL = "http://127.0.0.1:8080/process"
ORACLE = "/app/telemetry_oracle"


def oracle_result(payload):
    proc = subprocess.run(
        [ORACLE],
        input=payload.hex() + "\n",
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert proc.returncode == 0, f"Oracle failed: {proc.stdout}\n{proc.stderr}"
    try:
        return json.loads(proc.stdout)
    except ValueError as exc:
        pytest.fail(f"Oracle returned invalid JSON: {proc.stdout!r}: {exc}")


def assert_server_matches(payload):
    expected = oracle_result(payload)
    try:
        response = requests.post(URL, data=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server or send request: {exc}")

    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}; body={response.text!r}"
    )
    try:
        actual = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert actual == expected, f"For payload {payload.hex()}: expected {expected}, got {actual}"


def test_server_valid_request():
    payload = b'\x01\x41\x42\x00\x00\x00\x00\x05'
    assert_server_matches(payload)
    response = requests.post(URL, data=payload, timeout=5)
    data = response.json()
    assert data.get("version") == 1
    assert data.get("device_id") == "AB"
    assert data.get("metric") == 5


def test_server_corrupted_request():
    payload = b'\x01\x41\xFF\x00\x00\x00\x00\x05'
    assert_server_matches(payload)
    response = requests.post(URL, data=payload, timeout=5)
    data = response.json()
    assert data.get("version") == 1
    assert data.get("device_id") == "A?"
    assert data.get("metric") == 5


def test_server_oracle_equivalence_on_unpredictable_corruption():
    rng = secrets.SystemRandom()
    alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"

    device_ids = [
        b"pre\x80post",
        b"\xff\xfe\xfd",
        b"utf8-\xc3\xa9-end",
        b"A\x80\x81B\xfeC",
        b"\x80edge",
        b"edge\xff",
    ]

    for _ in range(18):
        length = rng.randint(1, 48)
        raw = bytearray(alphabet[rng.randrange(len(alphabet))] for _ in range(length))
        corruption_count = rng.randint(1, min(8, length))
        for position in rng.sample(range(length), corruption_count):
            raw[position] = rng.randint(128, 255)
        device_ids.append(bytes(raw))

    for device_id in device_ids:
        version = rng.randint(0, 255)
        metric = rng.randint(0, 0xFFFFFFFF)
        payload = bytes([version]) + device_id + b"\x00" + metric.to_bytes(4, "big")
        assert_server_matches(payload)


def test_exact_regression_commit_was_bisected():
    proc = subprocess.run(
        ["git", "log", "--all", "--format=%H%x09%s"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    )
    matches = []
    for line in proc.stdout.splitlines():
        commit, _, subject = line.partition("\t")
        if subject == "Refactor parsing to avoid allocations":
            matches.append(commit)
    assert len(matches) == 1, f"Could not uniquely identify regression commit: {matches}"
    culprit = matches[0]

    subprocess.run(
        ["git", "merge-base", "--is-ancestor", culprit, "HEAD"],
        cwd=REPO,
        check=True,
    )

    bad_source = subprocess.run(
        ["git", "show", f"{culprit}:src/main.rs"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    good_source = subprocess.run(
        ["git", "show", f"{culprit}^:src/main.rs"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    assert "from_utf8_lossy" in good_source
    assert "from_utf8" in bad_source and ".unwrap()" in bad_source

    reflog = subprocess.run(
        ["git", "reflog", "--all", "--format=%H%x09%gs"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    visited = any(
        line.startswith(culprit + "\t")
        and ("checkout: moving" in line or "bisect" in line.lower())
        for line in reflog.splitlines()
    )
    assert visited, (
        f"Git history identifies {culprit} as the regression, but the reflog does not "
        "show that commit being examined during the requested bisect"
    )


def test_rust_unit_test_added_and_detects_regression():
    main_rs = os.path.join(REPO, "src", "main.rs")
    assert os.path.exists(main_rs), f"Missing main.rs at {main_rs}"

    with open(main_rs, "r", encoding="utf-8") as handle:
        content = handle.read()
    assert "#[test]" in content, "No Rust unit test found in src/main.rs"

    proc = subprocess.run(
        ["cargo", "test"],
        cwd=REPO,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert proc.returncode == 0, f"cargo test failed:\n{proc.stdout}\n{proc.stderr}"

    with tempfile.TemporaryDirectory(prefix="telemetry_mutation_") as tmp:
        copied = os.path.join(tmp, "repo")
        shutil.copytree(
            REPO,
            copied,
            ignore=shutil.ignore_patterns("target", ".git"),
        )
        copied_main = os.path.join(copied, "src", "main.rs")
        with open(copied_main, "r", encoding="utf-8") as handle:
            mutated = handle.read()

        signature = re.compile(
            r"(fn\s+parse_telemetry\s*\(\s*buf\s*:\s*&\[u8\]\s*\)\s*"
            r"->\s*Result\s*<\s*String\s*,\s*&\s*'static\s+str\s*>\s*\{)"
        )
        injection = r'''\1
    // Verifier mutation: recreate incorrect recovery for a corrupted device ID.
    if buf.get(1..).unwrap_or(&[]).iter().take_while(|&&b| b != 0).any(|&b| b > 127) {
        return Ok("__incorrect_corrupted_device_recovery__".to_string());
    }
'''
        mutated, count = signature.subn(injection, mutated, count=1)
        assert count == 1, "Could not locate parse_telemetry to validate the regression test"

        with open(copied_main, "w", encoding="utf-8") as handle:
            handle.write(mutated)

        mutant_test = subprocess.run(
            ["cargo", "test"],
            cwd=copied,
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert mutant_test.returncode != 0, (
            "The Rust tests still pass when corrupted device-ID recovery is deliberately "
            "broken; the added #[test] does not assert the recovered result"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
