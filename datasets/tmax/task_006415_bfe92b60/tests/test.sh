#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import random
import re
import secrets
import stat
import subprocess
from pathlib import Path

import pytest


def test_detector_go_exists():
    path = "/home/user/detector.go"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."


def test_run_detector_script_exists_and_executable():
    path = "/home/user/run_detector.sh"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable by the owner."


def test_anomalies_output_correct():
    path = "/home/user/anomalies.out"
    assert os.path.exists(path), f"File {path} does not exist. Did you run your script manually?"

    with open(path, 'r') as f:
        content = f.read().strip()

    expected_lines = [
        "[2023-10-25T14:30:05Z] and [2023-10-25T14:30:06Z] - Similarity: 0.80",
        "[2023-10-25T14:30:20Z] and [2023-10-25T14:30:21Z] - Similarity: 1.00"
    ]

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {path}, found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch in {path}.\nExpected: {expected}\nActual:   {actual}"


def test_cron_job_configured():
    try:
        result = subprocess.run(['crontab', '-l'], capture_output=True, text=True, check=True)
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Is it configured for the user?")

    script_path = "/home/user/run_detector.sh"
    has_job = False
    for line in crontab_output.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if script_path in line and line.startswith('* * * * *'):
            has_job = True
            break

    assert has_job, f"Could not find cron job '* * * * * {script_path}' in crontab."


def _normalized_words(message):
    return set(re.sub(r'[^a-z0-9]', ' ', message.lower()).split())


def _expected(records):
    ordered = sorted(records, key=lambda record: record[0])
    result = []
    for left, right in zip(ordered, ordered[1:]):
        t1, ts1, _, msg1 = left
        t2, ts2, _, msg2 = right
        words1 = _normalized_words(msg1)
        words2 = _normalized_words(msg2)
        union = words1 | words2
        similarity = len(words1 & words2) / len(union) if union else 0.0
        if (t2 - t1).total_seconds() <= 2.0 and similarity >= 0.75:
            result.append(f"[{ts1}] and [{ts2}] - Similarity: {similarity:.2f}")
    return result


def _make_case(day):
    def word():
        return "w" + secrets.token_hex(6)

    a = [word() for _ in range(5)]
    b = [word() for _ in range(4)]
    c = [word() for _ in range(4)]
    base = datetime.datetime(2040, 6, day, 12, 0, 0, tzinfo=datetime.timezone.utc)

    entries = [
        (0,  "10.20.0.1", f"{a[0]}, {a[1]} {a[1]}! {a[2]}...{a[3]}"),
        (2,  "10.20.0.2", f"{a[0].upper()} {a[1]} {a[2]} {a[3]} {a[4]}"),
        (5,  "10.20.0.3", f"{a[0]} {a[1]} {a[2]} {a[3]} {a[4]}"),
        (10, "10.20.0.4", f"{b[0]}-{b[1]} / {b[2]} ({b[3]})"),
        (11, "10.20.0.5", f"{b[0].upper()} {b[1].upper()} {b[2].upper()} {b[3].upper()}"),
        (20, "10.20.0.6", f"{c[0]} {c[1]} {c[2]} {c[3]}"),
        (22, "10.20.0.7", f"{c[0].upper()}!!! {c[1]}, {c[2]}"),
        (23, "10.20.0.8", f"{c[0]} {c[1]}"),
    ]

    records = []
    for seconds, ip, message in entries:
        timestamp = base + datetime.timedelta(seconds=seconds)
        timestamp_text = timestamp.strftime('%Y-%m-%dT%H:%M:%SZ')
        records.append((timestamp, timestamp_text, ip, message))

    random.SystemRandom().shuffle(records)
    return records


def _write_log(records):
    lines = [f"{ts} | {ip} | {message}" for _, ts, ip, message in records]
    Path('/home/user/logs/raw.log').write_text('\n'.join(lines) + '\n')


def _read_output():
    path = Path('/home/user/anomalies.out')
    assert path.is_file(), "Detector did not create /home/user/anomalies.out"
    return [line.strip() for line in path.read_text().splitlines() if line.strip()]


def test_compiled_detector_and_wrapper_process_unseen_logs():
    raw_path = Path('/home/user/logs/raw.log')
    output_path = Path('/home/user/anomalies.out')
    original_raw = raw_path.read_bytes()
    original_output = output_path.read_bytes() if output_path.exists() else None
    binary = Path('/tmp/detector_verified')

    try:
        compile_result = subprocess.run(
            ['go', 'build', '-o', str(binary), '/home/user/detector.go'],
            cwd='/home/user', capture_output=True, text=True, timeout=60
        )
        assert compile_result.returncode == 0, (
            "detector.go did not compile:\n" + compile_result.stdout + compile_result.stderr
        )

        direct_records = _make_case(17)
        direct_expected = _expected(direct_records)
        _write_log(direct_records)
        output_path.unlink(missing_ok=True)

        direct_result = subprocess.run(
            [str(binary)], cwd='/home/user', capture_output=True, text=True, timeout=30
        )
        assert direct_result.returncode == 0, (
            "Compiled detector failed:\n" + direct_result.stdout + direct_result.stderr
        )
        assert _read_output() == direct_expected

        append_result = subprocess.run(
            [str(binary)], cwd='/home/user', capture_output=True, text=True, timeout=30
        )
        assert append_result.returncode == 0, (
            "Compiled detector failed on a second run:\n" + append_result.stdout + append_result.stderr
        )
        assert _read_output() == direct_expected + direct_expected, (
            "Detector must append anomaly lines rather than overwrite existing output"
        )

        wrapper_records = _make_case(18)
        wrapper_expected = _expected(wrapper_records)
        _write_log(wrapper_records)
        output_path.unlink(missing_ok=True)

        wrapper_result = subprocess.run(
            ['/home/user/run_detector.sh'], cwd='/home/user',
            capture_output=True, text=True, timeout=60
        )
        assert wrapper_result.returncode == 0, (
            "run_detector.sh failed:\n" + wrapper_result.stdout + wrapper_result.stderr
        )
        assert _read_output() == wrapper_expected, (
            "run_detector.sh did not compile/run the detector correctly on unseen input"
        )
    finally:
        raw_path.write_bytes(original_raw)
        if original_output is None:
            output_path.unlink(missing_ok=True)
        else:
            output_path.write_bytes(original_output)
        binary.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
