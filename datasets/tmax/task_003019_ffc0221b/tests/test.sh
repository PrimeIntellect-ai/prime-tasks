#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import struct
import subprocess
import uuid

import pytest

FILTER_BIN = "/home/user/filter_signal"
FILTER_SRC = "/home/user/filter_signal.c"
EVIL_CORPUS = "/app/corpus/evil"
CLEAN_CORPUS = "/app/corpus/clean"


def run_filter(executable, path):
    return subprocess.run(
        [executable, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=3,
    )


def f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def expected_result(values):
    if any(not math.isfinite(value) for value in values):
        return 1, "EVIL"

    sum_lr = f32(0.0)
    for value in values:
        sum_lr = f32(sum_lr + value)

    sum_rl = f32(0.0)
    for value in reversed(values):
        sum_rl = f32(sum_rl + value)

    diff = abs(f32(sum_lr - sum_rl))
    return (1, "EVIL") if diff > 0.01 else (0, "CLEAN")


def write_signal(path, values):
    with open(path, "wb") as handle:
        handle.write(struct.pack(f"<{len(values)}f", *values))


def assert_classification(executable, path, expected_code, expected_stdout):
    result = run_filter(executable, path)
    assert result.returncode == expected_code, (
        f"{executable} returned {result.returncode} for {path}; "
        f"expected {expected_code}. stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected_stdout, (
        f"{executable} printed {result.stdout!r} for {path}; "
        f"expected {expected_stdout!r}"
    )


def test_filter_binary_exists():
    assert os.path.exists(FILTER_BIN), f"Expected compiled binary at {FILTER_BIN} does not exist."
    assert os.path.isfile(FILTER_BIN), f"{FILTER_BIN} is not a file."
    assert os.access(FILTER_BIN, os.X_OK), f"{FILTER_BIN} is not executable."
    with open(FILTER_BIN, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", f"{FILTER_BIN} is not a compiled ELF binary."


def test_filter_source_exists():
    assert os.path.isfile(FILTER_SRC), f"Expected C source at {FILTER_SRC} does not exist."
    assert os.path.getsize(FILTER_SRC) > 0, f"{FILTER_SRC} is empty."


@pytest.fixture(scope="session")
def executables(tmp_path_factory):
    rebuilt = tmp_path_factory.mktemp("rebuilt") / "filter_signal"
    compilation = subprocess.run(
        ["gcc", "-std=c11", "-O2", FILTER_SRC, "-lm", "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert compilation.returncode == 0, (
        f"The submitted C source did not compile: {compilation.stderr}"
    )
    return [FILTER_BIN, str(rebuilt)]


def test_evil_corpus_rejected():
    evil_files = [
        os.path.join(EVIL_CORPUS, name)
        for name in os.listdir(EVIL_CORPUS)
        if os.path.isfile(os.path.join(EVIL_CORPUS, name))
    ]
    assert len(evil_files) > 0, "No files found in evil corpus."

    bypassed = []
    for path in evil_files:
        result = run_filter(FILTER_BIN, path)
        if result.returncode != 1 or result.stdout.strip() != "EVIL":
            bypassed.append(os.path.basename(path))

    if bypassed:
        pytest.fail(
            f"{len(bypassed)} of {len(evil_files)} evil files bypassed the filter: "
            + ", ".join(bypassed)
        )


def test_clean_corpus_accepted():
    clean_files = [
        os.path.join(CLEAN_CORPUS, name)
        for name in os.listdir(CLEAN_CORPUS)
        if os.path.isfile(os.path.join(CLEAN_CORPUS, name))
    ]
    assert len(clean_files) > 0, "No files found in clean corpus."

    modified = []
    for path in clean_files:
        result = run_filter(FILTER_BIN, path)
        if result.returncode != 0 or result.stdout.strip() != "CLEAN":
            modified.append(os.path.basename(path))

    if modified:
        pytest.fail(
            f"{len(modified)} of {len(clean_files)} clean files were rejected by the filter: "
            + ", ".join(modified)
        )


def test_unseen_signals(executables, tmp_path):
    rng = random.SystemRandom()
    cases = []

    # Paired clean and unstable inputs use overlapping lengths and neutral,
    # randomized filenames, preventing classification based on paths or sizes.
    for _ in range(16):
        length = rng.randint(17, 220)

        repeated = f32(rng.uniform(-500.0, 500.0))
        cases.append([repeated] * length)

        half = [f32(rng.uniform(-100.0, 100.0)) for _ in range(length // 2)]
        palindrome = half + ([f32(rng.uniform(-100.0, 100.0))] if length % 2 else []) + list(reversed(half))
        cases.append(palindrome)

        magnitude = float(2 ** rng.randint(35, 60))
        small = f32(rng.choice([0.25, 0.5, 1.0, 2.0, 3.0]))
        unstable = [magnitude, -magnitude] + [small] * (length - 2)
        if rng.choice([True, False]):
            unstable.reverse()
        cases.append(unstable)

        ordinary = [f32(rng.uniform(10.0, 100.0)) for _ in range(length)]
        cases.append(ordinary)

    # Non-finite values must be rejected regardless of position or surrounding data.
    cases.extend([
        [1.0, float("nan"), 2.0],
        [float("inf"), 1.0, 2.0],
        [1.0, 2.0, float("-inf")],
        [float("inf"), float("-inf")],
        [1.0] * 37 + [float("nan")],
    ])

    rng.shuffle(cases)
    observed_codes = set()

    for values in cases:
        filename = f"sample_{uuid.uuid4().hex}.dat"
        path = tmp_path / filename
        write_signal(path, values)
        expected_code, expected_stdout = expected_result(values)
        observed_codes.add(expected_code)

        for executable in executables:
            assert_classification(
                executable, str(path), expected_code, expected_stdout
            )

    assert observed_codes == {0, 1}, "Generated tests did not exercise both outcomes."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
