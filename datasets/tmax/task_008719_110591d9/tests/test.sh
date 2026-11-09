#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile

APP_DIR = "/home/user/app"
HASH_C = os.path.join(APP_DIR, "hash.c")
MAIN_C = os.path.join(APP_DIR, "main.c")
BUILD_SH = os.path.join(APP_DIR, "build.sh")
APP_BIN = os.path.join(APP_DIR, "app")
SUCCESS_LOG = os.path.join(APP_DIR, "success.log")
EXPECTED_OUTPUT = "Hash: 420\n"


def test_hash_c_patched():
    """Verify that hash.c has been patched to rename the function."""
    assert os.path.isfile(HASH_C), f"File {HASH_C} is missing."
    with open(HASH_C, "r") as f:
        content = f.read()
    assert "calculate_hash" in content, f"{HASH_C} does not contain 'calculate_hash'. The patch was likely not applied."
    assert "calc_hsh" not in content, f"{HASH_C} still contains 'calc_hsh'. The patch was likely not applied correctly."
    expected = "int calculate_hash(int val) {\n    return val * 42;\n}\n"
    assert content == expected, f"{HASH_C} is not the result of applying the captured patch."


def test_app_binary_exists():
    """Verify that the application was successfully built."""
    assert os.path.isfile(APP_BIN), f"Binary {APP_BIN} does not exist. Did the build succeed?"
    assert os.access(APP_BIN, os.X_OK), f"Binary {APP_BIN} is not executable."


def test_success_log():
    """Verify that the success.log contains the expected output."""
    assert os.path.isfile(SUCCESS_LOG), f"Log file {SUCCESS_LOG} does not exist. Did you run the app and redirect output?"
    with open(SUCCESS_LOG, "r") as f:
        content = f.read().strip()

    expected = "Hash: 420"
    assert content == expected, f"Content of {SUCCESS_LOG} is incorrect. Expected '{expected}', got '{content}'."


def test_build_and_execute_real_application():
    """Rebuild from scratch, verify an ELF was produced, and execute it."""
    assert os.path.isfile(BUILD_SH), f"Build script {BUILD_SH} is missing."
    assert os.access(BUILD_SH, os.X_OK), f"Build script {BUILD_SH} is not executable."

    if os.path.lexists(APP_BIN):
        os.unlink(APP_BIN)

    built = subprocess.run(
        [BUILD_SH], cwd=APP_DIR, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert built.returncode == 0, f"build.sh failed:\n{built.stdout}{built.stderr}"
    assert os.path.exists(APP_BIN), "build.sh did not create ./app."
    mode = os.lstat(APP_BIN).st_mode
    assert stat.S_ISREG(mode), "./app is not a regular binary file."
    assert os.access(APP_BIN, os.X_OK), "The rebuilt ./app is not executable."
    with open(APP_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The rebuilt ./app is not an ELF binary."

    symbols = subprocess.run(
        ["/usr/bin/nm", "--defined-only", APP_BIN],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert symbols.returncode == 0, f"Unable to inspect rebuilt binary: {symbols.stderr}"
    assert "calculate_hash" in symbols.stdout, "The rebuilt binary does not define calculate_hash."
    assert "calc_hsh" not in symbols.stdout, "The rebuilt binary still defines calc_hsh."

    run = subprocess.run(
        [APP_BIN], cwd=APP_DIR, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert run.returncode == 0, f"The rebuilt application failed: {run.stderr}"
    assert run.stdout == EXPECTED_OUTPUT, f"Unexpected application output: {run.stdout!r}"

    with open(SUCCESS_LOG, "r") as f:
        logged = f.read()
    assert logged == run.stdout, "success.log is not the exact standard output of the rebuilt application."

    with tempfile.TemporaryDirectory() as tmp:
        independent_app = os.path.join(tmp, "app")
        compiled = subprocess.run(
            ["/usr/bin/gcc", MAIN_C, HASH_C, "-o", independent_app],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert compiled.returncode == 0, f"The patched sources do not compile independently: {compiled.stderr}"
        independent = subprocess.run(
            [independent_app], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=10
        )
        assert independent.returncode == 0, f"Independently compiled application failed: {independent.stderr}"
        assert independent.stdout == EXPECTED_OUTPUT
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
