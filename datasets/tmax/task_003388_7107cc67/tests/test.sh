#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from decimal import Decimal, getcontext

import pytest

getcontext().prec = 80

AGGREGATOR = "/app/vendored/parallel-log-calc-1.0.4/bin/aggregate.sh"
SANITIZER = "/home/user/sanitize.sh"


def run_aggregator(directory, timeout=30):
    result = subprocess.run(
        [AGGREGATOR, directory],
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Aggregator failed for {directory}: stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    output = result.stdout.strip()
    assert output, "Aggregator produced no output"
    try:
        return Decimal(output)
    except Exception:
        pytest.fail(f"Aggregator output is not one valid decimal number: {output!r}")


def run_sanitizer(path, timeout=5, cwd=None):
    return subprocess.run(
        ["/bin/bash", SANITIZER, path],
        capture_output=True,
        timeout=timeout,
        cwd=cwd,
    )


def test_git_forensics_recovered_file():
    env_file = "/home/user/pipeline-config/math_thresholds.env"
    assert os.path.exists(env_file), f"Recovered file not found at {env_file}"

    with open(env_file, "r") as f:
        content = f.read()

    assert "PRECISION_SCALE=20" in content, "Missing PRECISION_SCALE=20 in recovered file"
    assert "MAX_LATENCY_THRESHOLD=999.999" in content, "Missing MAX_LATENCY_THRESHOLD=999.999 in recovered file"


def test_vendored_package_aggregation_result():
    result_file = "/home/user/aggregated_result.txt"
    test_logs_dir = "/home/user/test_logs"

    assert os.path.isfile(AGGREGATOR), f"Aggregator not found at {AGGREGATOR}"
    assert os.access(AGGREGATOR, os.X_OK), "Aggregator is not executable"
    with open(AGGREGATOR, "r", errors="replace") as f:
        source = f.read()
    assert source.startswith("#!") and "bash" in source.splitlines()[0], "Aggregator is not a Bash script"
    assert re.search(r"\bbc\s+-l\b|\bbc\s+[^\n]*\s-l\b", source), "Aggregator does not use bc -l arithmetic"

    assert os.path.exists(result_file), f"Aggregated result file not found at {result_file}"

    expected_sum = Decimal("0")
    for root, _, files in os.walk(test_logs_dir):
        for filename in files:
            filepath = os.path.join(root, filename)
            with open(filepath, "r") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    parts = line.split()
                    if parts:
                        try:
                            expected_sum += Decimal(parts[0])
                        except Exception:
                            pass

    with open(result_file, "r") as f:
        actual_result_str = f.read().strip()
    assert actual_result_str, "Aggregated result file is empty"
    try:
        actual_sum = Decimal(actual_result_str)
    except Exception:
        pytest.fail(f"Aggregated result {actual_result_str!r} is not a valid number")

    assert expected_sum == actual_sum, f"Aggregated sum mismatch. Expected {expected_sum}, got {actual_sum}"

    executed_sum = run_aggregator(test_logs_dir)
    assert executed_sum == expected_sum, (
        f"Executing the repaired aggregator gave {executed_sum}, expected {expected_sum}"
    )


def make_aggregation_case(parent, case_number):
    directory = os.path.join(parent, f"case_{case_number}_{secrets.token_hex(4)}")
    os.mkdir(directory)
    expected = Decimal("0")
    for file_number in range(24):
        path = os.path.join(directory, f"worker log {file_number} {secrets.token_hex(3)}.txt")
        with open(path, "w") as f:
            for line_number in range(8):
                whole = 10**18 + secrets.randbelow(10**12) + case_number * 10**13
                fraction = secrets.randbelow(10**12)
                value = f"{whole}.{fraction:012d}"
                f.write(value + "\n")
                expected += Decimal(value)
    return directory, expected


def test_aggregator_handles_unseen_spaced_files_precision_and_races():
    with tempfile.TemporaryDirectory(prefix="aggregate_dynamic_") as parent:
        cases = [make_aggregation_case(parent, i) for i in range(4)]

        # A fresh, unseen dataset catches fixed answers and stale accumulation files.
        assert run_aggregator(cases[0][0]) == cases[0][1]
        assert run_aggregator(cases[0][0]) == cases[0][1]

        # Independent simultaneous runs must not corrupt one another through shared temp files.
        processes = [
            subprocess.Popen([AGGREGATOR, directory], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            for directory, _ in cases
        ]
        for process, (_, expected) in zip(processes, cases):
            stdout, stderr = process.communicate(timeout=30)
            assert process.returncode == 0, f"Concurrent aggregator failed: {stderr!r}"
            try:
                actual = Decimal(stdout.strip())
            except Exception:
                pytest.fail(f"Concurrent aggregator emitted invalid output: {stdout!r}")
            assert actual == expected, f"Concurrent aggregation corruption: expected {expected}, got {actual}"


def test_adversarial_corpus_sanitization():
    assert os.path.exists(SANITIZER), f"Sanitize script not found at {SANITIZER}"
    assert os.path.isfile(SANITIZER), f"Sanitize path is not a regular file: {SANITIZER}"
    syntax = subprocess.run(["/bin/bash", "-n", SANITIZER], capture_output=True)
    assert syntax.returncode == 0, f"Sanitize script has invalid Bash syntax: {syntax.stderr!r}"

    clean_corpus_dir = "/home/user/corpora/clean"
    evil_corpus_dir = "/home/user/corpora/evil"
    clean_files = [os.path.join(clean_corpus_dir, f) for f in os.listdir(clean_corpus_dir) if os.path.isfile(os.path.join(clean_corpus_dir, f))]
    evil_files = [os.path.join(evil_corpus_dir, f) for f in os.listdir(evil_corpus_dir) if os.path.isfile(os.path.join(evil_corpus_dir, f))]

    failed_clean = []
    failed_evil = []
    for fpath in clean_files:
        if run_sanitizer(fpath).returncode != 0:
            failed_clean.append(os.path.basename(fpath))
    for fpath in evil_files:
        if run_sanitizer(fpath).returncode != 1:
            failed_evil.append(os.path.basename(fpath))

    error_msgs = []
    if failed_clean:
        error_msgs.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        error_msgs.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed/accepted: {', '.join(failed_evil)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_sanitizer_validates_unseen_contents_and_filenames():
    with tempfile.TemporaryDirectory(prefix="sanitize_dynamic_") as directory:
        valid_cases = [
            "2024-02-29T23:59:59Z 1.0\n",
            "2025-01-01T00:00:00Z 0.000001\n2025-01-01T00:00:01Z 999999999999.999999\n",
            f"2026-09-11T12:34:56Z {secrets.randbelow(999999) + 1}.{secrets.randbelow(1000000):06d}\n",
        ]
        for index, content in enumerate(valid_cases):
            path = os.path.join(directory, f"fresh_valid_{index}_{secrets.token_hex(4)}.log")
            with open(path, "w") as f:
                f.write(content)
            assert run_sanitizer(path).returncode == 0, f"Rejected unseen valid input {content!r}"

        invalid_contents = [
            "2025-01-01T00:00:00Z NaN\n",
            "2025-01-01T00:00:00Z Infinity\n",
            "2025-01-01T00:00:00Z -1.2\n",
            "2025-01-01T00:00:00Z 1.1234567\n",
            "2025-01-01T00:00:00Z 1e10\n",
            "1.234567\n",
            "2025-01-01T00:00:00Z 1.2 unexpected\n",
            "2025-01-01T00:00:00Z 1e" + ("9" * 5000) + "\n",
        ]
        for index, content in enumerate(invalid_contents):
            path = os.path.join(directory, f"fresh_invalid_{index}_{secrets.token_hex(4)}.log")
            with open(path, "w") as f:
                f.write(content)
            assert run_sanitizer(path).returncode == 1, f"Accepted unseen invalid input number {index}"

        marker = os.path.join(directory, "PWNED")
        malicious_names = [
            "bad;touch PWNED.log",
            "bad$(touch PWNED).log",
            "bad`touch PWNED`.log",
            "bad\nname.log",
        ]
        for name in malicious_names:
            path = os.path.join(directory, name)
            with open(path, "w") as f:
                f.write("2025-01-01T00:00:00Z 12.345678\n")
            assert run_sanitizer(path, cwd=directory).returncode == 1, f"Accepted malicious filename {name!r}"
            assert not os.path.exists(marker), f"Filename command injection created {marker}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
