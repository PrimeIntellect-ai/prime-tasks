#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

SANITIZER = "/home/user/bin/sanitizer"
PROJECT = "/home/user/sanitizer_project"


def test_anomaly_seconds():
    path = "/home/user/anomaly_seconds.txt"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert len(lines) == 2, f"Expected exactly 2 lines in {path}, found {len(lines)}."

    seconds = set()
    for line in lines:
        try:
            seconds.add(int(line))
        except ValueError:
            pytest.fail(f"Invalid integer found in {path}: {line}")

    assert seconds == {3, 7}, f"Expected anomaly seconds {{3, 7}}, but got {seconds}."


def test_sanitizer_executable_exists():
    assert os.path.isfile(SANITIZER), f"Sanitizer executable {SANITIZER} is missing."
    assert os.access(SANITIZER, os.X_OK), f"Sanitizer {SANITIZER} is not executable."
    with open(SANITIZER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The installed sanitizer must be a compiled native executable."


def test_rust_project_and_release_binary():
    assert os.path.isdir(PROJECT), f"Rust project {PROJECT} is missing."
    manifest = os.path.join(PROJECT, "Cargo.toml")
    src_dir = os.path.join(PROJECT, "src")
    assert os.path.isfile(manifest), f"Cargo manifest {manifest} is missing."
    assert os.path.isdir(src_dir), f"Rust source directory {src_dir} is missing."
    assert any(name.endswith(".rs") for _, _, files in os.walk(src_dir) for name in files), \
        "No Rust source files were found in the project."

    cargo = "/home/user/.cargo/bin/cargo"
    assert os.path.isfile(cargo) and os.access(cargo, os.X_OK), "Cargo is unavailable."

    env = os.environ.copy()
    env.update({
        "HOME": "/home/user",
        "CARGO_HOME": "/home/user/.cargo",
        "RUSTUP_HOME": "/home/user/.rustup",
        "PATH": "/home/user/.cargo/bin:" + env.get("PATH", ""),
    })

    with tempfile.TemporaryDirectory(prefix="sanitizer-release-") as target_dir:
        proc = subprocess.run(
            [cargo, "build", "--release", "--manifest-path", manifest,
             "--target-dir", target_dir, "--message-format=json-render-diagnostics", "--color", "never"],
            cwd=PROJECT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
        assert proc.returncode == 0, f"Rust release build failed:\n{proc.stderr}\n{proc.stdout}"

        built_bins = []
        for line in proc.stdout.splitlines():
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if event.get("reason") == "compiler-artifact" and "bin" in event.get("target", {}).get("kind", []):
                executable = event.get("executable")
                if executable and os.path.isfile(executable):
                    built_bins.append(executable)

        assert built_bins, "Cargo did not produce a release binary target."

        with open(SANITIZER, "rb") as f:
            installed_digest = hashlib.sha256(f.read()).digest()

        acceptable_digests = set()
        for built in built_bins:
            with open(built, "rb") as f:
                assert f.read(4) == b"\x7fELF", "Cargo's binary target is not a native executable."
            with open(built, "rb") as f:
                acceptable_digests.add(hashlib.sha256(f.read()).digest())

            stripped = built + ".stripped"
            shutil.copy2(built, stripped)
            strip_proc = subprocess.run(["strip", stripped], capture_output=True)
            if strip_proc.returncode == 0:
                with open(stripped, "rb") as f:
                    acceptable_digests.add(hashlib.sha256(f.read()).digest())

        assert installed_digest in acceptable_digests, \
            "The installed sanitizer does not match a freshly compiled release binary from the Rust project."


def test_sanitizer_adversarial_corpus():
    assert os.path.isfile(SANITIZER) and os.access(SANITIZER, os.X_OK), "Sanitizer executable not found or not executable"

    evil_dir = "/app/corpora/evil/"
    clean_dir = "/app/corpora/clean/"

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    clean_modified = []

    for f in evil_files:
        path = os.path.join(evil_dir, f)
        with open(path, 'rb') as fp:
            content = fp.read()
        proc = subprocess.run([SANITIZER], input=content, capture_output=True, timeout=10)
        output = proc.stdout.replace(b'\n', b'').replace(b'\r', b'')
        if output != b'':
            evil_bypassed.append(f)

    for f in clean_files:
        path = os.path.join(clean_dir, f)
        with open(path, 'rb') as fp:
            content = fp.read()
        proc = subprocess.run([SANITIZER], input=content, capture_output=True, timeout=10)

        expected = content.replace(b'\r\n', b'\n').strip()
        actual = proc.stdout.replace(b'\r\n', b'\n').strip()

        if expected != actual:
            clean_modified.append(f)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not error_msgs, "; ".join(error_msgs)


def _random_case(text):
    return "".join(ch.upper() if secrets.randbelow(2) else ch.lower() for ch in text)


def test_sanitizer_on_fresh_derived_inputs():
    # Fresh nonces and ordering prevent special-casing the shipped corpora.
    for _ in range(8):
        nonce = secrets.token_hex(16)
        clean = [
            f"{nonce} ordinary user login completed",
            f"{nonce} query executed: select item from inventory",
            f"{nonce} words drop and table occur separately",
            f"{nonce} literal script documentation without markup",
        ]
        evil = [
            f"{nonce} prefix {_random_case('DROP TABLE')} audit_events suffix",
            f"{nonce} prefix {_random_case('UNION SELECT')} secret_value suffix",
            f"{nonce} prefix {_random_case('<script>')}alert(9)</script> suffix",
            f"{nonce} URL={_random_case('javascript:')}alert(9)",
            f"{nonce} terminal payload \x1b[31mred",
        ]

        tagged = [(line, True) for line in clean] + [(line, False) for line in evil]
        random.SystemRandom().shuffle(tagged)
        payload = b"".join(line.encode("utf-8") + b"\n" for line, _ in tagged)
        expected = b"".join(line.encode("utf-8") + b"\n" for line, safe in tagged if safe)

        proc = subprocess.run([SANITIZER], input=payload, capture_output=True, timeout=10)
        assert proc.returncode == 0, f"Sanitizer exited with status {proc.returncode}: {proc.stderr!r}"
        assert proc.stdout == expected, \
            f"Sanitizer failed on freshly generated mixed input. Expected {expected!r}, got {proc.stdout!r}."


def test_sanitized_anomalies():
    path = "/home/user/sanitized_anomalies.txt"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = ["Anomaly trace 1", "Anomaly trace 2"]

    assert lines == expected_lines, f"Expected lines {expected_lines} in {path}, but got {lines}."

    with sqlite3.connect("/app/raw_logs.db") as db:
        messages = [row[0] for row in db.execute(
            "SELECT message FROM logs WHERE timestamp_sec IN (?, ?) ORDER BY id", (3, 7)
        )]
    payload = "".join(message + "\n" for message in messages).encode()
    proc = subprocess.run([SANITIZER], input=payload, capture_output=True, timeout=10)
    assert proc.returncode == 0
    assert proc.stdout.decode().splitlines() == expected_lines, \
        "The sanitizer does not produce the saved extraction when run on the anomaly database rows."


def test_cron_schedule():
    path = "/home/user/pipeline.cron"
    assert os.path.isfile(path), f"Cron schedule file {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip() and not line.startswith('#')]
    assert len(lines) > 0, f"No active cron jobs found in {path}."

    valid_cron_found = False
    for line in lines:
        if "/home/user/run_pipeline.sh" in line:
            if line.startswith("*/15 * * * *") or line.startswith("0,15,30,45 * * * *"):
                valid_cron_found = True
                break

    assert valid_cron_found, f"Could not find a valid cron schedule for every 15 minutes running /home/user/run_pipeline.sh in {path}. Found: {content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
