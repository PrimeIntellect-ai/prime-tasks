#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import secrets
import subprocess
import tempfile
from collections import Counter
from datetime import datetime, timezone

import pytest

EXECUTABLE = "/home/user/log_detector"


def run_detector(path, *extra_args):
    try:
        return subprocess.run(
            [EXECUTABLE, path, *extra_args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("log_detector timed out")


def write_csv(path, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "user_id", "message"])
        writer.writerows(rows)


def iso8601(epoch):
    return datetime.fromtimestamp(epoch, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def levenshtein(a, b):
    # Python strings are Unicode codepoints, matching the required metric.
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def test_log_detector_executable_exists():
    """Ensure the log_detector executable exists and is a native executable."""
    assert os.path.isfile(EXECUTABLE), f"Executable not found: {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File is not executable: {EXECUTABLE}"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "log_detector must be a compiled native executable, not a script"


def test_argument_handling(tmp_path):
    sample = tmp_path / "argument_sample.csv"
    write_csv(sample, [["2023-10-25T14:00:00Z", "u", "ordinary message"]])

    no_args = subprocess.run([EXECUTABLE], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    too_many = subprocess.run(
        [EXECUTABLE, str(sample), str(sample)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert no_args.returncode != 0, "invocation without the required CSV path must fail"
    assert too_many.returncode != 0, "invocation with more than one argument must fail"


def test_clean_corpus():
    """Ensure all original clean corpus files return exit code 0."""
    clean_dir = "/app/verifier/corpus/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    assert len(clean_files) > 0, f"No clean files found in {clean_dir}"

    failed_files = []
    for file_path in clean_files:
        if run_detector(file_path).returncode != 0:
            failed_files.append(os.path.basename(file_path))
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    """Ensure all original evil corpus files return exit code 1."""
    evil_dir = "/app/verifier/corpus/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))
    assert len(evil_files) > 0, f"No evil files found in {evil_dir}"

    failed_files = []
    for file_path in evil_files:
        if run_detector(file_path).returncode != 1:
            failed_files.append(os.path.basename(file_path))
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed/accepted. Offending files: {', '.join(failed_files)}")


def test_generated_unicode_levenshtein_cases(tmp_path):
    """Exercise generated message inputs and derive each expected result."""
    rng = random.SystemRandom()
    base_epoch = (1698242400 // 600) * 600

    messages = [
        "firewall",
        "firewal",
        "🔥firewall",
        "界界firewall",
        "界界界firewall",
        "fіrewall",  # Cyrillic і: one Unicode-codepoint substitution.
        "ordinary multilingual text こんにちは",
    ]

    # Produce additional unpredictable edit combinations at verification time.
    insertion_chars = ["界", "🔥", "Ж", "é", "λ"]
    for edit_count in range(6):
        value = list("firewall")
        for _ in range(edit_count):
            operation = rng.choice(["insert", "replace", "delete"])
            if operation == "insert" or not value:
                value.insert(rng.randrange(len(value) + 1), rng.choice(insertion_chars))
            elif operation == "replace":
                value[rng.randrange(len(value))] = rng.choice(insertion_chars)
            else:
                del value[rng.randrange(len(value))]
        messages.append("".join(value))

    saw_clean = saw_evil = False
    for index, message in enumerate(messages):
        expected = 1 if levenshtein(message, "firewall") <= 2 else 0
        saw_evil |= expected == 1
        saw_clean |= expected == 0
        path = tmp_path / f"generated_{secrets.token_hex(8)}_{index}.csv"
        write_csv(path, [[iso8601(base_epoch), f"user{index}", message]])
        result = run_detector(str(path))
        assert result.returncode == expected, (
            f"wrong result for generated Unicode Levenshtein case: "
            f"distance={levenshtein(message, 'firewall')}, returncode={result.returncode}"
        )

    assert saw_clean and saw_evil


def test_generated_embedded_newline_csv(tmp_path):
    """A quoted multiline field must remain one CSV record and not corrupt later rows."""
    base_epoch = (1698242400 // 600) * 600
    rows = [
        [iso8601(base_epoch + 1), "alpha", "Hello, quoted field\nこんにちは\nnot suspicious"],
        [iso8601(base_epoch + 2), "beta", "another ordinary message"],
    ]
    path = tmp_path / f"multiline_{secrets.token_hex(12)}.csv"
    write_csv(path, rows)
    assert run_detector(str(path)).returncode == 0

    rows.append([iso8601(base_epoch + 3), "gamma", "firewall"])
    flagged_path = tmp_path / f"multiline_flagged_{secrets.token_hex(12)}.csv"
    write_csv(flagged_path, rows)
    assert run_detector(str(flagged_path)).returncode == 1


def test_generated_bucket_boundaries(tmp_path):
    """Verify epoch-aligned ten-minute buckets and the strict >50 threshold."""
    rng = random.SystemRandom()
    base = ((1700000000 + rng.randrange(0, 100000)) // 600) * 600

    cases = []
    cases.append([(base + rng.randrange(600), i) for i in range(50)])
    cases.append([(base + rng.randrange(600), i) for i in range(51)])
    cases.append(
        [(base + rng.randrange(600), i) for i in range(50)] +
        [(base + 600 + rng.randrange(600), 50 + i) for i in range(50)]
    )

    # Additional unpredictable distributions; expected answers are computed
    # independently from floor(epoch / 600) bucket counts.
    for _ in range(8):
        generated = []
        for i in range(rng.randrange(35, 120)):
            bucket_offset = rng.randrange(0, 4)
            generated.append((base + bucket_offset * 600 + rng.randrange(600), i))
        cases.append(generated)

    for case_number, events in enumerate(cases):
        counts = Counter(epoch // 600 for epoch, _ in events)
        expected = 1 if max(counts.values(), default=0) > 50 else 0
        rows = [
            [iso8601(epoch), f"u{identifier}", "routine status message"]
            for epoch, identifier in events
        ]
        rng.shuffle(rows)
        path = tmp_path / f"bucket_{secrets.token_hex(10)}_{case_number}.csv"
        write_csv(path, rows)
        result = run_detector(str(path))
        assert result.returncode == expected, (
            f"wrong result for generated bucket counts {sorted(counts.values())}: "
            f"expected {expected}, got {result.returncode}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
