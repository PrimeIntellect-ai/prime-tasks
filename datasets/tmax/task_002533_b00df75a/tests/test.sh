#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pwd
import random
import shutil
import subprocess
import tempfile
import uuid

import pytest

SOLUTION = "/home/user/solution"
SOURCE = "/home/user/obfuscator.c"
ORACLE = "/app/oracle.bin"


def run_program(path, data, *, as_user=False):
    kwargs = {}
    if as_user:
        account = pwd.getpwnam("user")

        def demote():
            os.setgid(account.pw_gid)
            os.setuid(account.pw_uid)

        kwargs["preexec_fn"] = demote

    try:
        return subprocess.run(
            [path],
            input=data,
            capture_output=True,
            check=True,
            timeout=1,
            **kwargs,
        ).stdout
    except subprocess.CalledProcessError as exc:
        pytest.fail(
            f"{path} exited with status {exc.returncode} for input {data.hex()}: "
            f"{exc.stderr!r}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{path} timed out for input {data.hex()}")


def expected_output(data):
    assert len(data) == 64
    output = bytearray(data)
    state = 0xDEADBEEF
    for i in range(64):
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        output[i] ^= (state >> 24) & 0xFF
    return bytes(output)


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            digest.update(chunk)
    return digest.digest()


@pytest.fixture(scope="session")
def rebuilt_solution():
    assert os.path.lexists(SOURCE), f"Recovered source {SOURCE} does not exist."
    assert not os.path.islink(SOURCE), f"Recovered source {SOURCE} must not be a symlink."
    assert os.path.isfile(SOURCE), f"Recovered source {SOURCE} is not a regular file."

    build_dir = tempfile.mkdtemp(prefix="verify_source_", dir="/tmp")
    os.chmod(build_dir, 0o755)
    rebuilt = os.path.join(build_dir, "rebuilt_solution")
    try:
        result = subprocess.run(
            ["gcc", "-std=c11", "-O2", SOURCE, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            "The recovered obfuscator.c does not compile successfully.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        os.chmod(rebuilt, 0o755)
        yield rebuilt
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


def test_solution_exists_and_executable():
    solution_path = SOLUTION
    assert os.path.exists(solution_path), f"The solution executable {solution_path} does not exist."
    assert os.path.isfile(solution_path), f"The path {solution_path} is not a file."
    assert os.access(solution_path, os.X_OK), f"The file {solution_path} is not executable."


def test_solution_is_independent_elf():
    assert not os.path.islink(SOLUTION), "The solution must not be a symlink."
    assert not os.path.samefile(SOLUTION, ORACLE), "The solution must not be the oracle or a hard link to it."
    assert sha256(SOLUTION) != sha256(ORACLE), "The solution is byte-identical to the supplied oracle."
    with open(SOLUTION, "rb") as stream:
        header = stream.read(20)
    assert header[:4] == b"\x7fELF", "The solution must be a compiled ELF executable."
    assert len(header) >= 20 and header[4] == 2, "The solution must be a 64-bit ELF executable."
    machine = int.from_bytes(header[18:20], "little" if header[5] == 1 else "big")
    assert machine == 62, "The solution must target Linux x86_64."


def test_recovered_source_and_solution_work_without_oracle(rebuilt_solution):
    cases = [
        bytes(64),
        bytes([0, 1] * 32),
        bytes([1] * 63 + [0]),
        bytes(range(64)),
        bytes([255 - i for i in range(64)]),
    ]
    rng = random.Random(20250308)
    cases.extend(bytes(rng.randrange(256) for _ in range(64)) for _ in range(128))

    stash = os.path.join("/root", ".verifier_stash_" + uuid.uuid4().hex)
    os.mkdir(stash, 0o700)
    hidden_oracle = os.path.join(stash, "oracle.bin")
    hidden_solution = os.path.join(stash, "solution")

    os.rename(ORACLE, hidden_oracle)
    os.rename(SOLUTION, hidden_solution)
    try:
        for data in cases:
            actual = run_program(rebuilt_solution, data, as_user=True)
            assert actual == expected_output(data), (
                "The program compiled from obfuscator.c is incorrect.\n"
                f"Input: {data.hex()}\nExpected: {expected_output(data).hex()}\n"
                f"Actual: {actual.hex()}"
            )

        os.rename(hidden_solution, SOLUTION)
        for data in cases:
            actual = run_program(SOLUTION, data, as_user=True)
            assert actual == expected_output(data), (
                "The submitted solution is incorrect when the oracle is unavailable.\n"
                f"Input: {data.hex()}\nExpected: {expected_output(data).hex()}\n"
                f"Actual: {actual.hex()}"
            )
    finally:
        if os.path.exists(hidden_solution) and not os.path.exists(SOLUTION):
            os.rename(hidden_solution, SOLUTION)
        if os.path.exists(hidden_oracle) and not os.path.exists(ORACLE):
            os.rename(hidden_oracle, ORACLE)
        shutil.rmtree(stash, ignore_errors=True)


def test_fuzz_equivalence():
    oracle_path = ORACLE
    solution_path = SOLUTION

    assert os.path.exists(oracle_path), f"Oracle {oracle_path} missing."
    assert os.access(oracle_path, os.X_OK), f"Oracle {oracle_path} not executable."
    assert os.path.exists(solution_path), f"Solution {solution_path} missing."

    random.seed(42)
    N = 1000
    input_size = 64

    for i in range(N):
        test_input = bytes(random.choices(range(256), k=input_size))

        try:
            oracle_proc = subprocess.run(
                [oracle_path],
                input=test_input,
                capture_output=True,
                check=True,
                timeout=1,
            )
            oracle_output = oracle_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle crashed on iteration {i} with input {test_input.hex()}: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on iteration {i} with input {test_input.hex()}")

        try:
            solution_proc = subprocess.run(
                [solution_path],
                input=test_input,
                capture_output=True,
                check=True,
                timeout=1,
            )
            solution_output = solution_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Solution crashed on iteration {i} with input {test_input.hex()}: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Solution timed out on iteration {i} with input {test_input.hex()}")

        assert oracle_output == solution_output, (
            f"Mismatch on iteration {i}.\n"
            f"Input (hex): {test_input.hex()}\n"
            f"Oracle output (hex): {oracle_output.hex()}\n"
            f"Solution output (hex): {solution_output.hex()}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
