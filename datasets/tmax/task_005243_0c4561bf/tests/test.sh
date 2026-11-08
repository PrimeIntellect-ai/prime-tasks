#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import struct
import subprocess
import tempfile
import pytest

FILTER_BIN = "/home/user/filter"
FILTER_SRC = "/home/user/filter.c"
EVAL_CLEAN_DIR = "/eval/corpus/clean"
EVAL_EVIL_DIR = "/eval/corpus/evil"


def run_filter(executable, filepath):
    return subprocess.run(
        [executable, filepath], capture_output=True, timeout=3
    ).returncode


def test_filter_executable_exists():
    assert os.path.isfile(FILTER_BIN), f"Filter binary not found at {FILTER_BIN}"
    assert os.access(FILTER_BIN, os.X_OK), f"Filter binary at {FILTER_BIN} is not executable"
    with open(FILTER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled filter is not an ELF executable"


def test_filter_source_exists_and_compiles():
    assert os.path.isfile(FILTER_SRC), f"C source not found at {FILTER_SRC}"
    rebuilt = os.path.join(tempfile.mkdtemp(prefix="rebuilt_"), "candidate")
    result = subprocess.run(
        ["gcc", "-O2", FILTER_SRC, "-o", rebuilt],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"filter.c does not compile:\n{result.stderr}"
    with open(rebuilt, "rb") as f:
        assert f.read(4) == b"\x7fELF"


@pytest.fixture(scope="session")
def rebuilt_filter():
    output = os.path.join(tempfile.mkdtemp(prefix="source_filter_"), "filter")
    result = subprocess.run(
        ["gcc", "-O2", FILTER_SRC, "-o", output],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"filter.c does not compile:\n{result.stderr}"
    return output


def test_filter_is_not_linked_to_legacy_library():
    result = subprocess.run(
        ["readelf", "-d", FILTER_BIN], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, "Unable to inspect filter ELF dependencies"
    assert "libutils" not in result.stdout, "Filter is linked to the legacy parser library"
    assert "/app/lib" not in result.stdout, "Filter embeds the legacy library path"


def test_filter_clean_corpus():
    assert os.path.isdir(EVAL_CLEAN_DIR), f"Clean eval corpus missing at {EVAL_CLEAN_DIR}"
    clean_files = [os.path.join(EVAL_CLEAN_DIR, f) for f in os.listdir(EVAL_CLEAN_DIR) if os.path.isfile(os.path.join(EVAL_CLEAN_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean eval corpus"

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([FILTER_BIN, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected (exit code != 0): {', '.join(failed_files)}")


def test_filter_evil_corpus():
    assert os.path.isdir(EVAL_EVIL_DIR), f"Evil eval corpus missing at {EVAL_EVIL_DIR}"
    evil_files = [os.path.join(EVAL_EVIL_DIR, f) for f in os.listdir(EVAL_EVIL_DIR) if os.path.isfile(os.path.join(EVAL_EVIL_DIR, f))]
    assert len(evil_files) > 0, "No files found in evil eval corpus"

    bypassed_files = []
    for filepath in evil_files:
        result = subprocess.run([FILTER_BIN, filepath], capture_output=True)
        if result.returncode == 0:
            bypassed_files.append(os.path.basename(filepath))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed the filter (exit code == 0): {', '.join(bypassed_files)}")


def classify_payload(data):
    if len(data) < 6 or data[:4] != b"TELE":
        return 0
    declared = struct.unpack("<H", data[4:6])[0]
    bytes_copied = min(declared, len(data) - 6)
    return 1 if bytes_copied > 128 else 0


def generated_cases():
    cases = [
        b"",
        b"T",
        b"TEL",
        b"TELE",
        b"TELE\x81",
        b"NOPE" + struct.pack("<H", 600) + os.urandom(600),
        b"TELE" + struct.pack("<H", 128) + os.urandom(128),
        b"TELE" + struct.pack("<H", 129) + os.urandom(128),
        b"TELE" + struct.pack("<H", 129) + os.urandom(129),
        b"TELE" + struct.pack("<H", 500) + os.urandom(17),
        b"TELE" + struct.pack("<H", 500) + os.urandom(300),
    ]
    for _ in range(50):
        magic = b"TELE" if secrets.randbelow(3) else os.urandom(4)
        declared = secrets.randbelow(700)
        available = secrets.randbelow(700)
        cases.append(magic + struct.pack("<H", declared) + os.urandom(available))
    random.SystemRandom().shuffle(cases)
    return cases


def exercise_generated_inputs(executable):
    directory = tempfile.mkdtemp(prefix="payloads_" + secrets.token_hex(6) + "_")
    # Every case is written to the same opaque path, so path labels cannot reveal
    # whether the current contents are safe or overflowing.
    path = os.path.join(directory, secrets.token_hex(12))
    cases = generated_cases()
    assert any(classify_payload(x) == 0 for x in cases)
    assert any(classify_payload(x) == 1 for x in cases)

    for index, data in enumerate(cases):
        with open(path, "wb") as f:
            f.write(data)
        expected = classify_payload(data)
        actual = run_filter(executable, path)
        if expected == 0:
            assert actual == 0, f"Generated safe payload #{index} was rejected"
        else:
            assert actual != 0, f"Generated overflowing payload #{index} was accepted"


def test_generated_content_based_inputs(FILTER=rebuild_filter if False else None):
    exercise_generated_inputs(FILTER_BIN)


def test_recompiled_source_on_generated_inputs(rebuilt_filter):
    exercise_generated_inputs(rebuilt_filter)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
