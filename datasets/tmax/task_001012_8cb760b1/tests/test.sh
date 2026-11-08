#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import resource
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/sanitizer.sh"
BINARY_PATH = "/app/bin/log_aggregator"
CLEAN_CORPUS = "/verify/corpus/clean"
EVIL_CORPUS = "/verify/corpus/evil"


def test_sanitizer_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"


def test_clean_corpus():
    if not os.path.exists(CLEAN_CORPUS):
        pytest.skip("Clean corpus not found")

    failed_files = []
    for filename in sorted(os.listdir(CLEAN_CORPUS)):
        filepath = os.path.join(CLEAN_CORPUS, filename)
        if not os.path.isfile(filepath):
            continue

        with open(filepath, "rb") as f:
            expected_content = f.read()

        result = subprocess.run(["bash", SCRIPT_PATH, filepath], capture_output=True)

        if result.returncode != 0 or result.stdout != expected_content:
            failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} clean files modified or rejected: {failed_files}"


def test_evil_corpus():
    if not os.path.exists(EVIL_CORPUS):
        pytest.skip("Evil corpus not found")

    failed_files = []
    for filename in sorted(os.listdir(EVIL_CORPUS)):
        filepath = os.path.join(EVIL_CORPUS, filename)
        if not os.path.isfile(filepath):
            continue

        result = subprocess.run(["bash", SCRIPT_PATH, filepath], capture_output=True)

        if result.returncode != 1 or result.stdout != b"":
            failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} evil files bypassed: {failed_files}"


def _disable_core_dumps():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def _generated_case(index):
    stamp = f"{secrets.randbelow(9999):04d}-{secrets.randbelow(12) + 1:02d}-{secrets.randbelow(28) + 1:02d}"
    token = secrets.token_hex(10)
    extra = secrets.token_hex(6)
    kind = index % 12

    if kind == 0:
        text = f"{stamp},INFO,{token}\n"
    elif kind == 1:
        text = f"{stamp},ERROR,\n{stamp},WARN,{token}"
    elif kind == 2:
        text = f"{stamp},FATAL,{token}\n"
    elif kind == 3:
        text = f"{stamp}, FATAL,\n{stamp},INFO,{token}\n"
    elif kind == 4:
        text = f"{stamp},fatal,\n"
    elif kind == 5:
        text = f"{stamp},FATAL, {token},{extra}\r\n"
    elif kind == 6:
        text = f"{stamp},INFO,{token}\n{stamp},FATAL,\n{stamp},WARN,{extra}\n"
    elif kind == 7:
        text = f"{stamp},FATAL"
    elif kind == 8:
        text = f"{stamp},FATAL,,{extra}\n"
    elif kind == 9:
        text = f"{stamp},INFO,{token}\r\n{stamp},FATAL,\r\n"
    elif kind == 10:
        text = f",FATAL,\n{stamp},INFO,{token}\n"
    else:
        text = f"{stamp},DEBUG,{token},{extra}\n\n{stamp},FATAL,{extra}"

    return text.encode("utf-8")


def test_randomized_cases_against_binary():
    assert os.path.isfile(BINARY_PATH), f"Binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary is not executable: {BINARY_PATH}"

    failures = []
    with tempfile.TemporaryDirectory(prefix=f"sanitizer-hidden-{secrets.token_hex(8)}-") as directory:
        for index in range(96):
            content = _generated_case(index)
            filepath = os.path.join(directory, f"case-{secrets.token_hex(12)}.csv")
            with open(filepath, "wb") as f:
                f.write(content)

            oracle = subprocess.run(
                [BINARY_PATH, filepath],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=3,
                preexec_fn=_disable_core_dumps,
            )
            result = subprocess.run(
                ["bash", SCRIPT_PATH, filepath],
                capture_output=True,
                timeout=3,
            )

            if oracle.returncode == 0:
                correct = result.returncode == 0 and result.stdout == content
            else:
                correct = result.returncode == 1 and result.stdout == b""

            if not correct:
                failures.append({
                    "case": index,
                    "oracle_returncode": oracle.returncode,
                    "sanitizer_returncode": result.returncode,
                    "stdout_length": len(result.stdout),
                })

    assert not failures, f"Sanitizer disagreed with log_aggregator on generated cases: {failures[:10]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
