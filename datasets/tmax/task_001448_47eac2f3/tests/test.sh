#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
import pytest

SOURCE = "/home/user/auth_gen.c"
BINARY = "/home/user/auth_gen"
VERIFY_SCRIPT = "/home/user/verify_tokens.py"
TARGET = "/home/user/target_traffic.txt"
FINAL_LOG = "/home/user/final_tokens.log"


def expected_line(timestamp, timezone):
    sign = 1 if timezone[3] == "+" else -1
    hours, minutes = map(int, timezone[4:].split(":")[:2])
    adjusted = (timestamp + sign * (hours * 3600 + minutes * 60)) & 0xFFFFFFFF
    token = adjusted ^ 0xCAFEBABE
    return f"{timestamp} {timezone} -> {token:08X}"


def run_records(binary, records, env=None):
    fd, input_path = tempfile.mkstemp(prefix="auth_gen_input_", text=True)
    try:
        with os.fdopen(fd, "w") as f:
            for timestamp, timezone in records:
                f.write(f"{timestamp} {timezone}\n")
        return subprocess.check_output(
            [binary, input_path], stderr=subprocess.STDOUT, timeout=10, env=env
        ).decode().splitlines()
    finally:
        if os.path.exists(input_path):
            os.remove(input_path)


@pytest.fixture(scope="session")
def rebuilt_binaries():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."
    normal = "/tmp/auth_gen_rebuilt"
    asan = "/tmp/auth_gen_asan"
    subprocess.check_call(["gcc", "-g", "-o", normal, SOURCE])
    subprocess.check_call([
        "gcc", "-g", "-fno-omit-frame-pointer", "-fsanitize=address",
        "-o", asan, SOURCE
    ])
    return normal, asan


def test_auth_gen_c_fixed_formula():
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "hours * 360)" not in content and "hours * 360 " not in content, \
        "The formula error (hours * 360) is still present in auth_gen.c"


def test_required_artifacts_exist():
    assert os.path.isfile(VERIFY_SCRIPT), f"File {VERIFY_SCRIPT} is missing."
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Compiled binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF binary."


def test_formula_on_derived_inputs(rebuilt_binaries):
    rebuilt, _ = rebuilt_binaries
    rng = random.SystemRandom()
    records = []
    for _ in range(16):
        timestamp = rng.randrange(1500000000, 1900000000)
        sign = rng.choice(["+", "-"])
        hours = rng.randrange(0, 15)
        minutes = rng.randrange(0, 60)
        records.append((timestamp, f"UTC{sign}{hours:02d}:{minutes:02d}"))

    expected = [expected_line(ts, tz) for ts, tz in records]
    assert run_records(rebuilt, records) == expected
    assert run_records(BINARY, records) == expected


def test_auth_gen_no_memory_corruption_on_long_input(rebuilt_binaries):
    _, asan = rebuilt_binaries
    timezone = "UTC+02:00_" + ("A" * 180)
    records = [(1625000000, timezone)]
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
    try:
        output = run_records(asan, records, env=env)
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"auth_gen has memory corruption or crashed on a long timezone. "
            f"Return code: {e.returncode}. Output:\n{e.output.decode(errors='replace')}"
        )
    assert output == [expected_line(*records[0])]
    assert run_records(BINARY, records) == [expected_line(*records[0])]


def test_final_tokens_log_contents():
    assert os.path.isfile(FINAL_LOG), f"File {FINAL_LOG} is missing."
    assert os.path.isfile(TARGET), f"File {TARGET} is missing."

    records = []
    with open(TARGET, "r") as f:
        for line in f:
            if line.strip():
                timestamp, timezone = line.split()
                records.append((int(timestamp), timezone))

    expected = [expected_line(ts, tz) for ts, tz in records]
    with open(FINAL_LOG, "r") as f:
        actual = [line.strip() for line in f if line.strip()]

    assert actual == expected, \
        f"{FINAL_LOG} does not contain the correctly calculated target tokens."
    assert run_records(BINARY, records) == expected, \
        "The submitted binary does not reproduce final_tokens.log from target_traffic.txt."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
