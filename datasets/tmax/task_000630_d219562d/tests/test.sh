#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import tempfile
import pytest

PROJECT_DIR = "/home/user/log_pipeline"
SANITIZER_BIN = os.path.join(PROJECT_DIR, "build", "sanitizer")


def run_sanitizer(binary, payload, timeout=2):
    try:
        result = subprocess.run(
            [binary],
            input=(payload + "\n").encode("utf-8"),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Sanitizer hung on payload: {payload!r}")
    return result.returncode


def expected_result(payload):
    if "[RECURSE]" in payload:
        return 1
    depth = 0
    for char in payload:
        if char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth < 0:
                return 1
    return 0 if depth == 0 else 1


@pytest.fixture(scope="session")
def fresh_sanitizer():
    assert os.path.isfile(os.path.join(PROJECT_DIR, "CMakeLists.txt")), "CMakeLists.txt is missing"
    assert os.path.isfile(os.path.join(PROJECT_DIR, "src", "parser.cpp")), "src/parser.cpp is missing"

    with tempfile.TemporaryDirectory(prefix="log_pipeline_build_") as build_dir:
        configured = subprocess.run(
            ["cmake", "-S", PROJECT_DIR, "-B", build_dir],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=120,
        )
        assert configured.returncode == 0, "Fresh CMake configuration failed:\n" + configured.stdout

        built = subprocess.run(
            ["cmake", "--build", build_dir, "--", "-j2"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=180,
        )
        assert built.returncode == 0, "Fresh project build failed:\n" + built.stdout

        binary = os.path.join(build_dir, "sanitizer")
        assert os.path.isfile(binary), "Fresh build did not produce the sanitizer executable"
        assert os.access(binary, os.X_OK), "Freshly built sanitizer is not executable"
        yield binary


def test_reconstructed_timeline():
    timeline_path = "/home/user/reconstructed_timeline.log"
    assert os.path.isfile(timeline_path), f"File {timeline_path} is missing."

    expected_lines = []
    for svc in ['a', 'b', 'c']:
        log_file = f"/home/user/logs/service_{svc}.log"
        if os.path.isfile(log_file):
            with open(log_file, 'r') as f:
                for line in f:
                    if line.startswith("2023-10-01T00:00:"):
                        expected_lines.append(line.strip())

    expected_lines.sort()

    with open(timeline_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, "The reconstructed timeline does not match the expected chronologically sorted logs for the 00:00 minute."


def test_sanitizer_adversarial_corpus():
    sanitizer_bin = SANITIZER_BIN
    assert os.path.isfile(sanitizer_bin), f"Sanitizer binary not found at {sanitizer_bin}"
    assert os.access(sanitizer_bin, os.X_OK), f"Sanitizer binary is not executable at {sanitizer_bin}"

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    clean_failures = []
    evil_failures = []

    clean_count = 0
    if os.path.isdir(clean_dir):
        for fname in sorted(os.listdir(clean_dir)):
            clean_count += 1
            fpath = os.path.join(clean_dir, fname)
            with open(fpath, 'rb') as f:
                try:
                    result = subprocess.run(
                        [sanitizer_bin], stdin=f, stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL, timeout=2
                    )
                    if result.returncode != 0:
                        clean_failures.append(fname)
                except subprocess.TimeoutExpired:
                    clean_failures.append(fname + " (timeout)")

    evil_count = 0
    if os.path.isdir(evil_dir):
        for fname in sorted(os.listdir(evil_dir)):
            evil_count += 1
            fpath = os.path.join(evil_dir, fname)
            with open(fpath, 'rb') as f:
                try:
                    result = subprocess.run(
                        [sanitizer_bin], stdin=f, stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL, timeout=2
                    )
                    if result.returncode != 1:
                        evil_failures.append(fname)
                except subprocess.TimeoutExpired:
                    evil_failures.append(fname + " (timeout)")

    error_msg = []
    if clean_failures:
        error_msg.append(f"{len(clean_failures)} of {clean_count} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_msg.append(f"{len(evil_failures)} of {evil_count} evil bypassed/accepted: {', '.join(evil_failures)}")

    assert not error_msg, " | ".join(error_msg)


def test_generated_sanitizer_cases(fresh_sanitizer):
    assert os.path.isfile(SANITIZER_BIN), f"Sanitizer binary not found at {SANITIZER_BIN}"
    assert os.access(SANITIZER_BIN, os.X_OK), f"Sanitizer binary is not executable at {SANITIZER_BIN}"

    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + " _-.:,/@#$%^&*+=!?"

    def text(minimum=0, maximum=14):
        return ''.join(rng.choice(alphabet) for _ in range(rng.randint(minimum, maximum)))

    def valid_fragment(depth=0):
        parts = [text()]
        if depth < 5:
            for _ in range(rng.randint(0, 3)):
                parts.append("[" + valid_fragment(depth + 1) + "]")
                parts.append(text())
        return ''.join(parts)

    cases = {
        "": 0,
        "plain payload": 0,
        "[balanced]tail": 0,
        "prefix[nested[content]]suffix": 0,
        "[RECURSEX]": 0,
        "[RECURSE ]": 0,
        "[": 1,
        "]": 1,
        "abc[unterminated": 1,
        "abc]unexpected": 1,
        "[RECURSE]": 1,
        "prefix[RECURSE]suffix": 1,
        "[a[RECURSE]b]": 1,
        "[" * 256 + "x" + "]" * 256: 0,
        "[" * 256 + "x" + "]" * 255: 1,
    }

    for _ in range(140):
        valid = valid_fragment()
        cases[valid] = expected_result(valid)
        cases[valid + "["] = 1
        cases["]" + valid] = 1
        cases[valid + "]"] = 1
        split = rng.randint(0, len(valid))
        circular = valid[:split] + "[RECURSE]" + valid[split:]
        cases[circular] = 1

    for payload, expected in cases.items():
        derived = expected_result(payload)
        assert derived == expected, f"Internal expectation mismatch for {payload!r}"
        for binary in (SANITIZER_BIN, fresh_sanitizer):
            actual = run_sanitizer(binary, payload)
            assert actual == expected, (
                f"{binary} returned {actual} for {payload!r}; expected {expected}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
