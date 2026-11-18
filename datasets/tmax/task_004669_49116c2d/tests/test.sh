#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import glob
import re
import secrets
import random
import string
import subprocess
import tempfile
from datetime import datetime, timedelta, timezone
import pytest


def test_json_sh_fix():
    json_sh_path = "/app/vendored/JSON.sh-0.4.1/JSON.sh"
    assert os.path.exists(json_sh_path), f"File missing: {json_sh_path}"

    # Retain the original regression check.
    payload = '{"test":"\\uabcd"}'
    result = subprocess.run(
        [json_sh_path, "-b"],
        input=payload,
        text=True,
        capture_output=True
    )

    assert result.returncode == 0, f"JSON.sh failed to execute. stderr: {result.stderr}"

    expected_output_fragment = '["test"]\t"\\uabcd"'
    assert expected_output_fragment in result.stdout, (
        f"JSON.sh did not correctly parse the hex unicode escape. "
        f"Expected to find '{expected_output_fragment}' in output, got:\n{result.stdout}"
    )

    # Exercise unpredictable four-digit escapes containing A-F/a-f so a fixed
    # response for the original payload cannot satisfy the regression test.
    rng = random.SystemRandom()
    for index in range(12):
        alphabet = string.digits + ("abcdef" if index % 2 else "ABCDEF")
        codepoint = [rng.choice(alphabet) for _ in range(4)]
        codepoint[rng.randrange(4)] = rng.choice("abcdef" if index % 2 else "ABCDEF")
        codepoint = "".join(codepoint)
        key = "field_" + secrets.token_hex(6)
        prefix = secrets.token_hex(3)
        suffix = secrets.token_hex(3)
        value = f"{prefix} \\u{codepoint} {suffix}"
        generated_payload = '{"%s":"%s"}' % (key, value)

        generated_result = subprocess.run(
            [json_sh_path, "-b"],
            input=generated_payload,
            text=True,
            capture_output=True,
            timeout=10,
        )
        expected = f'["{key}"]\t"{value}"'
        assert generated_result.returncode == 0, (
            f"JSON.sh rejected valid Unicode escape \\u{codepoint}: "
            f"{generated_result.stderr}"
        )
        assert expected in generated_result.stdout, (
            f"JSON.sh did not preserve valid Unicode escape \\u{codepoint}. "
            f"Expected {expected!r}, got {generated_result.stdout!r}"
        )


def test_anomaly_detector_corpus():
    detector_script = "/home/user/detect_anomalies.sh"
    assert os.path.exists(detector_script), f"Detector script missing: {detector_script}"
    assert os.access(detector_script, os.X_OK), f"Detector script is not executable: {detector_script}"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    evil_files = glob.glob(os.path.join(evil_dir, "*"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    for fpath in clean_files:
        result = subprocess.run([detector_script, fpath], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(fpath))

    evil_failed = []
    for fpath in evil_files:
        result = subprocess.run([detector_script, fpath], capture_output=True)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(fpath))

    error_messages = []
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")

    assert not error_messages, "Corpus verification failed:\n" + "\n".join(error_messages)


def _oracle_is_evil(contents):
    # Every literal Unicode escape introducer must have four following hex digits.
    position = 0
    while True:
        position = contents.find("\\u", position)
        if position < 0:
            break
        digits = contents[position + 2:position + 6]
        if len(digits) != 4 or re.fullmatch(r"[0-9A-Fa-f]{4}", digits) is None:
            return True
        position += 6

    timestamp_pattern = re.compile(r'"timestamp"\s*:\s*"([^"]+)"')
    previous = None
    for raw_timestamp in timestamp_pattern.findall(contents):
        current = datetime.fromisoformat(raw_timestamp.replace("Z", "+00:00"))
        if previous is not None and current < previous:
            return True
        previous = current
    return False


def _line(record_id, timestamp, message):
    return '{"id":%d,"timestamp":"%s","msg":"%s"}' % (
        record_id, timestamp, message
    )


def test_anomaly_detector_generated_inputs():
    detector_script = "/home/user/detect_anomalies.sh"
    assert os.path.exists(detector_script), f"Detector script missing: {detector_script}"
    assert os.access(detector_script, os.X_OK), f"Detector script is not executable: {detector_script}"

    rng = random.SystemRandom()
    cases = []
    base = datetime(2021, 1, 1, tzinfo=timezone.utc) + timedelta(
        days=rng.randrange(1500), seconds=rng.randrange(86400)
    )

    # Valid escapes with randomized letters and monotonic/equal timestamps.
    for case_index in range(5):
        times = []
        current = base + timedelta(days=case_index)
        for _ in range(rng.randrange(3, 7)):
            current += timedelta(seconds=rng.choice([0, 1, 7, 31, 90]))
            times.append(current)
        lines = []
        for row, stamp in enumerate(times):
            code = [rng.choice(string.hexdigits[:16]) for _ in range(4)]
            code[rng.randrange(4)] = rng.choice("aAbBcCdDeEfF")
            lines.append(_line(
                row,
                stamp.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "reading_" + secrets.token_hex(2) + " \\u" + "".join(code),
            ))
        cases.append("\n".join(lines) + "\n")

    # Random malformed escapes: an illegal character among the required digits.
    for case_index in range(4):
        chars = [rng.choice("0123456789abcdefABCDEF") for _ in range(4)]
        chars[rng.randrange(4)] = rng.choice("GHIJKLMNOPQRSTUVWXYZghijklmnopqrstuvwxyz")
        stamp = (base + timedelta(days=20 + case_index)).strftime("%Y-%m-%dT%H:%M:%SZ")
        cases.append(_line(case_index, stamp, "sensor \\u" + "".join(chars)) + "\n")

    # Random truncated escapes containing fewer than four hexadecimal digits.
    for case_index in range(3):
        short = "".join(rng.choice("0123456789abcdefABCDEF") for _ in range(rng.randrange(0, 4)))
        stamp = (base + timedelta(days=30 + case_index)).strftime("%Y-%m-%dT%H:%M:%SZ")
        cases.append(_line(case_index, stamp, "sensor \\u" + short) + "\n")

    # Backward timestamp jumps at unpredictable positions and magnitudes.
    for case_index in range(5):
        start = base + timedelta(days=40 + case_index)
        stamps = [start]
        for _ in range(rng.randrange(2, 5)):
            stamps.append(stamps[-1] + timedelta(seconds=rng.randrange(1, 120)))
        jump_at = rng.randrange(1, len(stamps))
        stamps[jump_at] = stamps[jump_at - 1] - timedelta(seconds=rng.randrange(1, 120))
        lines = [
            _line(row, stamp.strftime("%Y-%m-%dT%H:%M:%SZ"), "reading_" + secrets.token_hex(3))
            for row, stamp in enumerate(stamps)
        ]
        cases.append("\n".join(lines) + "\n")

    # Classifications are calculated from content, while all files share one
    # opaque directory and randomized filenames.
    rng.shuffle(cases)
    expected_results = [_oracle_is_evil(contents) for contents in cases]
    assert any(expected_results) and not all(expected_results)

    with tempfile.TemporaryDirectory(prefix="inputs_" + secrets.token_hex(6) + "_") as directory:
        failures = []
        for contents, expected_evil in zip(cases, expected_results):
            path = os.path.join(directory, secrets.token_hex(12) + ".dat")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(contents)
            result = subprocess.run(
                [detector_script, path],
                capture_output=True,
                timeout=10,
            )
            expected_code = 1 if expected_evil else 0
            if result.returncode != expected_code:
                failures.append(
                    f"{os.path.basename(path)} expected {expected_code}, got {result.returncode}"
                )
        assert not failures, "Generated anomaly checks failed:\n" + "\n".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
