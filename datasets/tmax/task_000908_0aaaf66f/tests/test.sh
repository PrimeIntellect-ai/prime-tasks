#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import subprocess

SCRIPT = "/home/user/detector.sh"
HEADER = "timestamp,incident_id,response_time,message"


def run_detector(content):
    return subprocess.run(
        [SCRIPT], input=content, text=True, capture_output=True, timeout=10
    )


def test_rolling_avg():
    expected = [
        "2023-10-25T08:12:01,INC-5581,105,105.00",
        "2023-10-25T08:12:15,INC-5581,110,107.50",
        "2023-10-25T08:13:00,INC-5581,110,108.33",
        "2023-10-25T08:14:22,INC-5581,120,113.33",
        "2023-10-25T08:15:05,INC-5581,115,115.00"
    ]
    file_path = "/home/user/rolling_avg.csv"
    assert os.path.exists(file_path), f"{file_path} is missing."
    with open(file_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert lines == expected, (
        f"{file_path} content mismatch.\nExpected:\n{expected}\nGot:\n{lines}"
    )


def test_detector_executable():
    assert os.path.exists(SCRIPT), f"{SCRIPT} is missing."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a regular file."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."


def test_detector_clean_corpus():
    clean_files = glob.glob("/app/corpus/clean/*.csv")
    assert clean_files, "No clean corpus files found."

    failed = []
    for path in clean_files:
        with open(path, "r") as fin:
            expected = fin.read().strip()
        proc = run_detector(expected)
        if proc.returncode != 0 or proc.stdout.strip() != expected:
            failed.append(os.path.basename(path))

    assert not failed, f"{len(failed)} of {len(clean_files)} clean modified: {failed}"


def test_detector_evil_corpus_preserves_valid_records():
    evil_files = glob.glob("/app/corpus/evil/*.csv")
    assert evil_files, "No evil corpus files found."

    expected = "\n".join([
        HEADER,
        '2023-10-25T08:12:01,INC-1111,105,"Message 1"',
    ])
    failed = []
    for path in evil_files:
        with open(path, "r") as fin:
            content = fin.read().strip()
        proc = run_detector(content)
        if proc.returncode != 0 or proc.stdout.strip() != expected:
            failed.append(os.path.basename(path))

    assert not failed, (
        f"{len(failed)} of {len(evil_files)} evil files were filtered incorrectly: {failed}"
    )


def test_detector_on_fresh_mixed_stream():
    # Fresh values prevent a detector specialized to the shipped corpus from passing.
    token = secrets.token_hex(8)
    incident = "INC-" + str(secrets.randbelow(9000) + 1000)
    forged_incident = "INC-" + str(secrets.randbelow(9000) + 1000)

    first = f'2041-06-17T09:01:02,{incident},137,"safe-{token}"'
    multiline = (
        f'2041-06-17T09:02:03,{incident},141,"legitimate-{token}\n'
        f'continuation-{token}"'
    )
    forged = (
        f'2041-06-17T09:03:04,{incident},150,"attacked-{token}\n'
        f'2041-06-17T09:03:05,{forged_incident},999,Injected-{token}"'
    )
    after = f'2041-06-17T09:04:05,{incident},,"after-{token}"'
    unquoted_message = f'2041-06-17T09:05:06,{incident},155,unquoted-{token}'

    content = "\n".join([
        HEADER,
        first,
        multiline,
        forged,
        after,
        unquoted_message,
    ])
    expected = "\n".join([HEADER, first, multiline, after])

    proc = run_detector(content)
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout.strip() == expected, (
        "Detector failed to preserve fresh valid records or reject fresh forged/malformed rows.\n"
        f"Expected:\n{expected!r}\nGot:\n{proc.stdout.strip()!r}"
    )


def test_detector_drops_unterminated_record_without_losing_prior_rows():
    token = secrets.token_hex(8)
    incident = "INC-" + str(secrets.randbelow(9000) + 1000)
    valid = f'2042-07-18T10:11:12,{incident},88,"valid-{token}"'
    malformed = f'2042-07-18T10:12:13,{incident},89,"unterminated-{token}'
    content = "\n".join([HEADER, valid, malformed])
    expected = "\n".join([HEADER, valid])

    proc = run_detector(content)
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout.strip() == expected, (
        "Detector did not drop an unterminated record correctly.\n"
        f"Expected:\n{expected!r}\nGot:\n{proc.stdout.strip()!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
