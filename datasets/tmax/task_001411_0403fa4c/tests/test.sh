#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import struct
import subprocess
import tempfile
import pytest

PARSEMAN_DIR = "/app/parseman-1.0"
DETECTOR_SOURCE = "/home/user/detector.c"
DETECTOR_BINARY = "/home/user/detector"


def run_checked(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=20, **kwargs)


def assert_elf(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable"


def test_parseman_built():
    parseman = os.path.join(PARSEMAN_DIR, "parseman")
    assert os.path.isfile(parseman), "parseman executable was not built in /app/parseman-1.0"
    assert os.access(parseman, os.X_OK), "/app/parseman-1.0/parseman is not executable"


def test_make_is_repaired_and_builds_parseman():
    parseman = os.path.join(PARSEMAN_DIR, "parseman")
    os.unlink(parseman)
    result = run_checked(["make", "-B"], cwd=PARSEMAN_DIR)
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(parseman), "make did not produce parseman"
    assert os.access(parseman, os.X_OK), "make produced a non-executable parseman"
    assert_elf(parseman)

    with tempfile.NamedTemporaryFile() as log:
        log.write(b"L0GZ" + bytes([1]) + struct.pack("<H", 3) + b"abc")
        log.flush()
        parsed = subprocess.run([parseman, log.name], capture_output=True, timeout=5)
        assert parsed.returncode == 0, "the parseman produced by make cannot process a valid log"


def test_detector_exists():
    assert os.path.isfile(DETECTOR_SOURCE), "/home/user/detector.c source file is missing"
    assert os.path.isfile(DETECTOR_BINARY), "/home/user/detector executable is missing"
    assert os.access(DETECTOR_BINARY, os.X_OK), "/home/user/detector is not executable"
    assert_elf(DETECTOR_BINARY)


def test_adversarial_corpus():
    evil_files = glob.glob("/app/corpus/evil/*")
    clean_files = glob.glob("/app/corpus/clean/*")
    assert len(evil_files) > 0, "No evil files found in corpus."
    assert len(clean_files) > 0, "No clean files found in corpus."

    evil_bypassed = []
    for evil_file in evil_files:
        result = subprocess.run([DETECTOR_BINARY, evil_file], capture_output=True, timeout=5)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    clean_modified = []
    for clean_file in clean_files:
        result = subprocess.run([DETECTOR_BINARY, clean_file], capture_output=True, timeout=5)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(clean_file))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def record(record_type, length):
    return bytes([record_type]) + struct.pack("<H", length) + os.urandom(length)


def test_detector_source_binary_and_dynamic_logs():
    rng = secrets.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="logcheck-") as td:
        rebuilt = os.path.join(td, "rebuilt-detector")
        compiled = run_checked(["gcc", "-std=gnu11", "-O2", DETECTOR_SOURCE, "-o", rebuilt])
        assert compiled.returncode == 0, f"detector.c does not compile:\n{compiled.stdout}\n{compiled.stderr}"
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
        assert_elf(rebuilt)

        cases = []
        for _ in range(28):
            safe_len = rng.randint(0, 64)
            large_safe_len = rng.randint(65, 900)
            safe_type = rng.choice([t for t in range(1, 256) if t != 5])
            data = b"L0GZ" + record(safe_type, large_safe_len) + record(5, safe_len)
            cases.append((data, 0))

        for _ in range(28):
            overflow_len = rng.randint(65, 900)
            prefix_type = rng.choice([t for t in range(1, 256) if t != 5])
            prefix_len = rng.randint(0, 180)
            data = b"L0GZ" + record(prefix_type, prefix_len) + record(5, overflow_len)
            cases.append((data, 1))

        rng.shuffle(cases)
        for index, (data, expected) in enumerate(cases):
            path = os.path.join(td, secrets.token_hex(12) + f"-{index}.dat")
            with open(path, "wb") as f:
                f.write(data)
            for detector in (DETECTOR_BINARY, rebuilt):
                result = subprocess.run([detector, path], capture_output=True, timeout=5)
                assert result.returncode == expected, (
                    f"{detector} misclassified generated case {index}: "
                    f"expected {expected}, got {result.returncode}"
                )

        for detector in (DETECTOR_BINARY, rebuilt):
            no_arg = subprocess.run([detector], capture_output=True, timeout=5)
            extra_arg = subprocess.run([detector, cases_path(td), cases_path(td)], capture_output=True, timeout=5)
            assert no_arg.returncode != 0, f"{detector} accepts zero arguments"
            assert extra_arg.returncode != 0, f"{detector} accepts more than one argument"


def cases_path(directory):
    return os.path.join(directory, "argument-placeholder")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
