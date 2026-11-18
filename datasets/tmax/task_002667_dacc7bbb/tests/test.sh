#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shlex
import struct
import subprocess
import tempfile

HOME = "/home/user"
MAKEFILE = os.path.join(HOME, "Makefile")
EXE = os.path.join(HOME, "test_runner")
DATA = os.path.join(HOME, "test_data.bin")
RESULT = os.path.join(HOME, "test_result.json")


def test_makefile_exists_and_flags():
    """Verify Makefile exists and contains required compiler flags."""
    assert os.path.exists(MAKEFILE), f"Makefile not found at {MAKEFILE}"

    with open(MAKEFILE, "r") as f:
        content = f.read()

    assert "g++" in content, "Makefile does not specify g++ as the compiler."
    assert "-std=c++17" in content, "Makefile does not contain the -std=c++17 flag."
    assert "-O2" in content, "Makefile does not contain the -O2 flag."


def test_build_executable():
    """Verify default make actually invokes g++ with the required flags."""
    if os.path.exists(EXE):
        os.remove(EXE)

    gpp = "/usr/bin/g++"
    assert os.path.exists(gpp), "System g++ is unavailable."
    real_gpp = os.path.realpath(gpp)
    log_path = tempfile.mktemp(prefix="gpp-arguments-")
    backup = tempfile.mktemp(prefix="gpp-backup-", dir="/usr/bin")

    os.rename(gpp, backup)
    try:
        wrapper = (
            "#!/bin/sh\n"
            f"printf '%s\\n' '---' >> {shlex.quote(log_path)}\n"
            f"printf '%s\\n' \"$@\" >> {shlex.quote(log_path)}\n"
            f"exec {shlex.quote(real_gpp)} \"$@\"\n"
        )
        with open(gpp, "w") as f:
            f.write(wrapper)
        os.chmod(gpp, 0o755)

        result = subprocess.run(
            ["make", "-C", HOME], capture_output=True, text=True, timeout=60
        )
    finally:
        if os.path.lexists(gpp):
            os.remove(gpp)
        os.rename(backup, gpp)

    assert result.returncode == 0, (
        f"make command failed with output:\n{result.stdout}\n{result.stderr}"
    )
    assert os.path.exists(EXE), f"Executable {EXE} was not created by make."
    assert os.access(EXE, os.X_OK), f"File {EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "test_runner is not a compiled ELF executable."

    assert os.path.exists(log_path), "The default make target did not invoke g++."
    with open(log_path) as f:
        invocations = [part.splitlines() for part in f.read().split("---") if part.strip()]
    assert any("-std=c++17" in args and "-O2" in args for args in invocations), (
        "No actual g++ invocation used both -std=c++17 and -O2."
    )


def run_and_load():
    if os.path.exists(RESULT):
        os.remove(RESULT)
    result = subprocess.run([EXE], cwd=HOME, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"test_runner failed with output:\n{result.stderr}"
    assert os.path.exists(RESULT), f"Output file {RESULT} was not created."

    with open(RESULT, "r") as f:
        raw = f.read()
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        assert False, f"File {RESULT} does not contain valid JSON."
    return raw, parsed


def test_run_executable_and_output():
    """Preserve the original fixture and expected-result assertions."""
    raw, data = run_and_load()
    assert "variance" in data, "JSON output missing 'variance' key."
    variance = data["variance"]
    assert isinstance(variance, (int, float)), "Variance must be a numerical value."
    assert abs(variance - 66.6667) < 1e-5, f"Expected variance to be 66.6667, got {variance}"


def expected_variance(records):
    active = False
    values = []
    for command, value in records:
        if command == 0x01:
            active = True
        elif command == 0x02:
            if active:
                values.append(value)
        elif command == 0x03:
            active = False
    if not values:
        return 0.0
    mean = sum(values) / len(values)
    return sum((value - mean) ** 2 for value in values) / len(values)


def write_records(records):
    with open(DATA, "wb") as f:
        for command, value in records:
            f.write(struct.pack("<Bd", command, value))


def test_state_machine_and_variance_on_derived_inputs():
    """Exercise parsing, state transitions, ignored commands, and variance."""
    fixtures = [
        [(0x02, 999.0), (0x03, 0.0), (0x7F, 4.0)],
        [(0x01, 4.0), (0x02, 3.0), (0x02, -7.0), (0x02, 12.5)],
        [(0x01, 0.0), (0x02, -2.0), (0x03, 0.0), (0x02, 500.0),
         (0x55, 9.0), (0x01, 0.0), (0x02, 8.0), (0x01, 0.0),
         (0x02, 14.0), (0x03, 0.0)],
    ]

    rng = random.SystemRandom()
    for _ in range(7):
        records = []
        for _ in range(rng.randrange(20, 45)):
            command = rng.choice([0x01, 0x02, 0x02, 0x02, 0x03, 0x19, 0xFE])
            value = rng.randrange(-2000, 2001) / 8.0
            records.append((command, value))
        fixtures.append(records)

    for records in fixtures:
        write_records(records)
        expected = expected_variance(records)
        raw, data = run_and_load()

        assert isinstance(data, dict), "Output JSON must be an object."
        assert set(data) == {"variance"}, "Output must contain only the variance key."
        assert isinstance(data["variance"], (int, float)) and not isinstance(data["variance"], bool), (
            "Variance must be a numerical value."
        )
        match = re.fullmatch(r'\{"variance": (-?\d+\.\d{4})\}\s*', raw)
        assert match, "Output must use the required JSON format with exactly four decimal places."
        expected_text = f"{expected:.4f}"
        assert match.group(1) == expected_text, (
            f"Expected variance {expected_text} for records {records!r}, got {match.group(1)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
