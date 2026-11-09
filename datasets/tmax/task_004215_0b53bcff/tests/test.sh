#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import subprocess
import tempfile
import uuid

import pytest

EXECUTABLE = "/home/user/run_filter"
SOURCE = "/home/user/filter.c"
LIBDIR = "/app/libfastcsv-0.9.3"
LIBRARY = os.path.join(LIBDIR, "libfastcsv.a")
EVIL_DIR = "/app/eval_data/evil/"
CLEAN_DIR = "/app/eval_data/clean/"
VERIFIED_EXECUTABLE = "/tmp/run_filter_verified"
LINK_MAP = "/tmp/run_filter_verified.map"


def run_filter(executable, path):
    return subprocess.run(
        [executable, path], capture_output=True, text=True, timeout=2
    )


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist. Did you compile your C program?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "run_filter must be a compiled ELF executable, not a script."


def test_adversarial_corpus():
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.csv"))
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.csv"))

    assert len(evil_files) > 0, f"No evil files found in {EVIL_DIR}."
    assert len(clean_files) > 0, f"No clean files found in {CLEAN_DIR}."

    evil_bypassed = []
    clean_modified = []

    for f in evil_files:
        try:
            result = run_filter(EXECUTABLE, f)
            if result.stdout.strip() != "REJECT":
                evil_bypassed.append(os.path.basename(f))
        except Exception:
            evil_bypassed.append(os.path.basename(f))

    for f in clean_files:
        try:
            result = run_filter(EXECUTABLE, f)
            if result.stdout.strip() != "ACCEPT":
                clean_modified.append(os.path.basename(f))
        except Exception:
            clean_modified.append(os.path.basename(f))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_repaired_library_and_source_build():
    assert os.path.isfile(SOURCE), f"Required source file {SOURCE} is missing."
    assert os.path.isfile(os.path.join(LIBDIR, "Makefile")), "The vendored Makefile is missing."

    build = subprocess.run(
        ["make", "-B", "libfastcsv.a"], cwd=LIBDIR,
        capture_output=True, text=True, timeout=20
    )
    assert build.returncode == 0, f"The repaired vendored Makefile cannot build libfastcsv.a:\n{build.stdout}\n{build.stderr}"
    assert "-O3" in build.stdout + build.stderr, "The vendored library build does not use -O3."
    assert os.path.isfile(LIBRARY), "make did not produce libfastcsv.a."

    archive = subprocess.run(["ar", "t", LIBRARY], capture_output=True, text=True, timeout=5)
    assert archive.returncode == 0 and "fastcsv.o" in archive.stdout.split(), "libfastcsv.a is not a valid archive containing fastcsv.o."

    compile_result = subprocess.run(
        [
            "gcc", "-O3", "-I" + LIBDIR, SOURCE, LIBRARY,
            "-Wl,-Map," + LINK_MAP, "-o", VERIFIED_EXECUTABLE
        ],
        capture_output=True, text=True, timeout=20
    )
    assert compile_result.returncode == 0, f"filter.c cannot be compiled at -O3 with libfastcsv.a:\n{compile_result.stdout}\n{compile_result.stderr}"
    assert os.path.isfile(VERIFIED_EXECUTABLE) and os.access(VERIFIED_EXECUTABLE, os.X_OK)

    with open(LINK_MAP, "r", errors="replace") as f:
        link_map = f.read()
    assert "libfastcsv.a(fastcsv.o)" in link_map, "filter.c does not reference and statically link the libfastcsv archive implementation."


def make_private_cases():
    rng = random.SystemRandom()
    root = tempfile.mkdtemp(prefix="csv_inputs_" + secrets.token_hex(8) + "_")
    cases = []

    for make_evil in ([False] * 12 + [True] * 12):
        rows = []
        count = rng.randint(3, 80)
        evil_position = rng.randrange(count) if make_evil else -1
        for index in range(count):
            want_evil = index == evil_position
            while True:
                alpha = rng.uniform(-40.0, 40.0)
                beta = rng.uniform(-40.0, 40.0)
                score = 2.5 * alpha - 1.2 * beta
                if want_evil and score > 12.0:
                    break
                if not want_evil and score < 8.0:
                    break
            rows.append((alpha, beta))

        path = os.path.join(root, uuid.uuid4().hex + ".csv")
        with open(path, "w") as f:
            f.write("sensor_alpha,sensor_beta\n")
            for alpha, beta in rows:
                f.write(f"{alpha:.17g},{beta:.17g}\n")

        expected = "REJECT" if any(2.5 * a - 1.2 * b > 10.0 for a, b in rows) else "ACCEPT"
        cases.append((path, expected))

    rng.shuffle(cases)
    return cases


def test_unlabeled_randomized_inputs_and_cli_contract():
    cases = make_private_cases()
    for executable in (EXECUTABLE, VERIFIED_EXECUTABLE):
        for path, expected in cases:
            result = run_filter(executable, path)
            assert result.returncode == 0, f"{executable} exited with {result.returncode} on a valid CSV"
            assert result.stdout.strip() == expected, f"{executable} returned the wrong decision for generated input {os.path.basename(path)}"
            assert result.stdout in ("ACCEPT\n", "REJECT\n", "ACCEPT", "REJECT"), "Output must contain exactly ACCEPT or REJECT."

        no_arg = subprocess.run([executable], capture_output=True, text=True, timeout=2)
        extra_arg = subprocess.run([executable, cases[0][0], cases[1][0]], capture_output=True, text=True, timeout=2)
        assert no_arg.returncode != 0, "The executable must reject invocation without exactly one path argument."
        assert extra_arg.returncode != 0, "The executable must reject invocation with more than one path argument."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
