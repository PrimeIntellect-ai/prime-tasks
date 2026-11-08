#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import string
import subprocess
from decimal import Decimal

import pytest

EXECUTABLES = ["/home/user/sanitizer", "/tmp/sanitizer_from_source"]


@pytest.fixture(scope="session", autouse=True)
def build_and_compile_source():
    source = "/home/user/sanitizer.c"
    makefile = "/home/user/Makefile"
    executable = "/home/user/sanitizer"
    source_executable = "/tmp/sanitizer_from_source"

    assert os.path.isfile(source), f"Source file missing: {source}"
    assert os.path.isfile(makefile), f"Makefile missing: {makefile}"

    if os.path.lexists(executable):
        os.remove(executable)

    built = subprocess.run(
        ["make", "-B", "-C", "/home/user", "sanitizer"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert built.returncode == 0, (
        f"Makefile build failed. stdout:\n{built.stdout}\nstderr:\n{built.stderr}"
    )

    compiled = subprocess.run(
        [
            "gcc", "-std=c99", "-Wall", "-Werror",
            "-Wimplicit-function-declaration", "-o", source_executable, source,
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compiled.returncode == 0, (
        f"sanitizer.c does not compile under the required flags. "
        f"stdout:\n{compiled.stdout}\nstderr:\n{compiled.stderr}"
    )

    for path in EXECUTABLES:
        assert os.path.isfile(path), f"Executable not found: {path}"
        assert os.access(path, os.X_OK), f"File is not executable: {path}"
        with open(path, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"Expected a compiled ELF executable: {path}"


def run_validator(path, data):
    return subprocess.run(
        [path], input=data.encode("utf-8"), capture_output=True, timeout=3
    ).returncode


def assert_all_accept(data):
    for executable in EXECUTABLES:
        rc = run_validator(executable, data)
        assert rc == 0, f"{executable} rejected valid input {data!r} with status {rc}"


def assert_all_reject(data):
    for executable in EXECUTABLES:
        rc = run_validator(executable, data)
        assert rc == 1, f"{executable} did not reject invalid input {data!r} with status 1 (got {rc})"


def test_sanitizer_executable_exists():
    executable_path = "/home/user/sanitizer"
    assert os.path.isfile(executable_path), f"Executable not found: {executable_path}"
    assert os.access(executable_path, os.X_OK), f"File is not executable: {executable_path}"


def test_clean_corpus_accepted():
    executable_path = "/home/user/sanitizer"
    clean_dir = "/app/clean"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, "No files found in clean corpus"

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        with open(filepath, "rb") as f:
            result = subprocess.run([executable_path], stdin=f, capture_output=True)
            if result.returncode != 0:
                failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified (rejected instead of accepted). Offending files: {', '.join(failed_files)}")


def test_evil_corpus_rejected():
    executable_path = "/home/user/sanitizer"
    evil_dir = "/app/evil"

    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, "No files found in evil corpus"

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        with open(filepath, "rb") as f:
            result = subprocess.run([executable_path], stdin=f, capture_output=True)
            if result.returncode == 0:
                failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed (accepted instead of rejected). Offending files: {', '.join(failed_files)}")


def test_generated_valid_inputs():
    rng = random.SystemRandom()
    allowed = string.ascii_letters + string.digits + "-_"

    fixed_names = ["A", "_", "-", "--__", "NODE_9-west"]
    for name in fixed_names:
        assert_all_accept(f"{name} 25.5 100.0\n")

    for _ in range(35):
        name = "".join(rng.choice(allowed) for _ in range(rng.randint(1, 60)))
        total = rng.randint(1000, 10000000)
        uptime = rng.randint(0, total - 10)
        assert (float(uptime) / float(total)) * 100.0 != 100.0
        suffix = "\n" if rng.choice([True, False]) else ""
        assert_all_accept(f"{name} {uptime}.0 {total}.0{suffix}")

    # Genuine 100% uptime is valid because uptime is not less than total.
    for _ in range(10):
        total = rng.randint(1, 1000000)
        assert_all_accept(f"equal-{rng.randint(1, 10**9)} {total}.0 {total}.0\n")


def test_generated_invalid_filenames():
    rng = random.SystemRandom()
    invalid_chars = [".", "/", ";", "$", "`", "'", '"', "*", "?", "[", "]", "(", ")", "&", "|", ">", "<", "!", "\\", ":", "é"]
    for bad in invalid_chars:
        left = "node" + str(rng.randint(1000, 9999))
        right = "log" + str(rng.randint(1000, 9999))
        assert_all_reject(f"{left}{bad}{right} 50.0 100.0\n")

    for _ in range(10):
        assert_all_reject(f"server {rng.randint(1, 999999)} 50.0 100.0\n")


def test_generated_logical_and_parsing_errors():
    rng = random.SystemRandom()

    for _ in range(25):
        total = rng.randint(1, 10000000)
        uptime = total + rng.randint(1, 100000)
        assert Decimal(str(uptime)) > Decimal(str(total))
        assert_all_reject(f"logic-{rng.randint(1, 10**9)} {uptime}.0 {total}.0\n")

    malformed = [
        "only-a-filename\n",
        "node 1.0\n",
        "node 1.0 2.0 extra\n",
        "node 1.0x 2.0\n",
        "node x1.0 2.0\n",
        "node 1.0 2.0x\n",
        "node 1.0 2.0\nsecond 1.0 2.0\n",
        "node 1.0 2.0\n\n",
        "\n",
        "",
    ]
    for data in malformed:
        assert_all_reject(data)


def test_generated_precision_loss_cases():
    rng = random.SystemRandom()

    # Construct decimal values that are truly less than total, but collapse to
    # the same binary64 value. The binary64 percentage therefore evaluates to 100.
    for _ in range(30):
        total_int = rng.randint(1000, 10000000)
        total_text = f"{total_int}.0"
        delta = Decimal(1).scaleb(-rng.randint(16, 24))
        uptime_decimal = Decimal(total_text) - delta
        uptime_text = format(uptime_decimal, "f")

        assert Decimal(uptime_text) < Decimal(total_text)
        uptime_float = float(uptime_text)
        total_float = float(total_text)
        assert uptime_float == total_float
        assert (uptime_float / total_float) * 100.0 == 100.0

        name = f"precision-{rng.randint(1, 10**9)}"
        assert_all_reject(f"{name} {uptime_text} {total_text}\n")

    # Being close to total is not itself grounds for rejection when the computed
    # percentage remains distinguishable from exactly 100.
    for _ in range(15):
        total_int = rng.randint(1000, 10000000)
        total_text = f"{total_int}.0"
        uptime_decimal = Decimal(total_text) - Decimal("0.01")
        uptime_text = format(uptime_decimal, "f")
        assert Decimal(uptime_text) < Decimal(total_text)
        assert (float(uptime_text) / float(total_text)) * 100.0 != 100.0
        assert_all_accept(f"near-{rng.randint(1, 10**9)} {uptime_text} {total_text}\n")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
