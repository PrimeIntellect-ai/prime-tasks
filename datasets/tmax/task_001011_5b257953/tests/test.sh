#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import importlib
import os
import random
import secrets
import shutil
import string
import subprocess
import sys

import pytest


def _clear_directory(path):
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path, exist_ok=True)


def _run_collector(script_path):
    return subprocess.run(
        ["python3", script_path],
        capture_output=True,
        text=True,
        timeout=60,
    )


def _assert_identical_directories(source_dir, destination_dir):
    source_files = os.listdir(source_dir)
    destination_files = os.listdir(destination_dir)

    assert len(destination_files) > 0, "No files were copied to /home/user/raw_logs/"
    assert len(destination_files) == len(source_files), (
        f"Expected {len(source_files)} files in raw_logs, but found "
        f"{len(destination_files)}."
    )
    assert set(destination_files) == set(source_files), (
        "The copied filenames do not exactly match the source filenames."
    )

    for filename in source_files:
        source_path = os.path.join(source_dir, filename)
        destination_path = os.path.join(destination_dir, filename)
        assert os.path.isfile(destination_path), f"Missing copied file: {filename}"
        with open(source_path, "rb") as source_handle:
            expected = source_handle.read()
        with open(destination_path, "rb") as destination_handle:
            actual = destination_handle.read()
        assert actual == expected, f"Copied content differs for {filename}"


def test_collect_diagnostics_success():
    """Preserve the original collector run and file-count assertions."""
    script_path = "/home/user/collect_diagnostics.py"
    assert os.path.isfile(script_path), f"Missing script {script_path}"

    source_logs_dir = "/tmp/source_logs/"
    raw_logs_dir = "/home/user/raw_logs/"
    assert os.path.isdir(source_logs_dir), f"Missing source logs directory at {source_logs_dir}"

    _clear_directory(raw_logs_dir)
    result = _run_collector(script_path)
    assert result.returncode == 0, (
        f"collect_diagnostics.py failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )

    assert os.path.isdir(raw_logs_dir), f"Missing raw logs directory at {raw_logs_dir}"
    _assert_identical_directories(source_logs_dir, raw_logs_dir)


def test_collect_diagnostics_randomized_exact_copies():
    """Exercise the collector on unpredictable names and contents over repeated runs."""
    script_path = "/home/user/collect_diagnostics.py"
    source_logs_dir = "/tmp/source_logs/"
    raw_logs_dir = "/home/user/raw_logs/"

    for round_number in range(3):
        _clear_directory(source_logs_dir)
        _clear_directory(raw_logs_dir)

        count = 35 + round_number * 5
        for index in range(count):
            token = secrets.token_hex(7)
            filename = f"node {index} batch {token} metrics.csv"
            payload = (
                f"metric1,metric2,nonce\n"
                f"{random.uniform(-5000, 5000):.12f},{random.uniform(-5000, 5000):.12f},{token}\n"
            ).encode("utf-8") + os.urandom(32 + index % 17)
            with open(os.path.join(source_logs_dir, filename), "wb") as handle:
                handle.write(payload)

        result = _run_collector(script_path)
        assert result.returncode == 0, (
            f"Randomized collector run {round_number} failed with exit code "
            f"{result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
        )
        _assert_identical_directories(source_logs_dir, raw_logs_dir)


def test_vendored_sh_concurrent_copy(tmp_path):
    """Import and directly exercise the required vendored sh artifact concurrently."""
    vendored_dir = "/app/vendored/sh-1.14.3"
    vendored_file = os.path.join(vendored_dir, "sh.py")
    assert os.path.isfile(vendored_file), f"Missing vendored library at {vendored_file}"

    sys.modules.pop("sh", None)
    sys.path.insert(0, vendored_dir)
    try:
        sh = importlib.import_module("sh")
    finally:
        sys.path.pop(0)

    assert os.path.realpath(sh.__file__) == os.path.realpath(vendored_file), (
        f"Loaded sh from the wrong location: {sh.__file__}"
    )

    source_dir = tmp_path / "sources with spaces"
    destination_dir = tmp_path / "destinations with spaces"
    source_dir.mkdir()
    destination_dir.mkdir()

    jobs = []
    for index in range(120):
        nonce = secrets.token_hex(8)
        source = source_dir / f"worker {index} {nonce}.csv"
        destination = destination_dir / f"copied worker {index} {nonce}.csv"
        data = os.urandom(64 + index % 31)
        source.write_bytes(data)
        jobs.append((source, destination, data))

    def copy_one(job):
        source, destination, _ = job
        sh.cp(str(source), str(destination))

    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        list(executor.map(copy_one, jobs))

    for _, destination, expected in jobs:
        assert destination.is_file(), f"Vendored sh failed to create {destination.name}"
        assert destination.read_bytes() == expected, (
            f"Vendored sh corrupted the contents of {destination.name}"
        )


def test_sanitizer_is_present_and_executable():
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_path), f"Missing sanitizer script at {sanitizer_path}"
    assert os.access(sanitizer_path, os.X_OK), f"Sanitizer is not executable: {sanitizer_path}"


def test_sanitizer_clean_corpus():
    """Preserve the original clean-corpus assertions."""
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_path), f"Missing sanitizer script at {sanitizer_path}"

    clean_dir = "/app/data/corpora/clean/"
    assert os.path.isdir(clean_dir), f"Missing clean corpus directory at {clean_dir}"

    clean_files = [
        f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))
    ]
    assert len(clean_files) > 0, "Clean corpus directory is empty"

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        result = subprocess.run(["python3", sanitizer_path, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_files)} clean modified "
            f"(rejected when they should be accepted). Offending files: "
            f"{', '.join(failed_files)}"
        )


def test_sanitizer_evil_corpus():
    """Preserve the original evil-corpus assertions."""
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_path), f"Missing sanitizer script at {sanitizer_path}"

    evil_dir = "/app/data/corpora/evil/"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory at {evil_dir}"

    evil_files = [
        f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))
    ]
    assert len(evil_files) > 0, "Evil corpus directory is empty"

    bypassed_files = []
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        result = subprocess.run(["python3", sanitizer_path, filepath], capture_output=True)
        if result.returncode != 1:
            bypassed_files.append(filename)

    if bypassed_files:
        pytest.fail(
            f"{len(bypassed_files)} of {len(evil_files)} evil bypassed "
            f"(accepted when they should be rejected). Offending files: "
            f"{', '.join(bypassed_files)}"
        )


def test_sanitizer_randomized_unlabeled_files(tmp_path):
    """Derive expectations while placing clean and poisoned files together under random names."""
    sanitizer_path = "/home/user/sanitizer.py"
    neutral_dir = tmp_path / secrets.token_hex(10)
    neutral_dir.mkdir()

    cases = []
    poison_tokens = ["NaN", "inf", "1e400"]
    for index in range(30):
        poisoned = bool(index % 2)
        rows = []
        poison_row = random.randrange(12) if poisoned else -1
        poison_column = random.choice((1, 2))

        for row_index in range(12):
            first = f"{random.uniform(-10000, 10000):.10f}"
            second = f"{random.uniform(-10000, 10000):.10f}"
            fields = [f"2026-01-01T12:{row_index:02d}:00Z", first, second]
            if row_index == poison_row:
                fields[poison_column] = random.choice(poison_tokens)
            rows.append(",".join(fields))

        random_name = "".join(secrets.choice(string.ascii_letters) for _ in range(18)) + ".csv"
        path = neutral_dir / random_name
        path.write_text("\n".join(rows) + "\n", encoding="utf-8")
        cases.append((path, 1 if poisoned else 0))

    random.shuffle(cases)
    failures = []
    for path, expected_status in cases:
        result = subprocess.run(
            ["python3", sanitizer_path, str(path)],
            capture_output=True,
            timeout=15,
        )
        if result.returncode != expected_status:
            failures.append((path.name, expected_status, result.returncode))

    assert not failures, f"Sanitizer misclassified randomized files: {failures}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
