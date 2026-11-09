#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import shutil
import subprocess

import pytest

SCRIPT = "/home/user/build_and_test.sh"
SOURCE = "/home/user/src/math_check.c"
EXE = "/home/user/bin/math_check"
DATA = "/home/user/test_data.txt"
LOG = "/home/user/test_report.log"


def clean_generated_files():
    shutil.rmtree("/home/user/bin", ignore_errors=True)
    for path in (DATA, LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_build_script():
    return subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def decoded_result(n):
    proc = subprocess.run(
        [EXE, str(n)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert proc.returncode == 0, f"math_check failed for {n}: {proc.stderr!r}"
    try:
        raw = base64.b64decode(proc.stdout.strip(), validate=True).decode("ascii")
        return int(raw)
    except Exception as exc:
        pytest.fail(f"math_check produced invalid Base64 integer for {n}: {proc.stdout!r} ({exc})")


@pytest.fixture(scope="session", autouse=True)
def execute_submission_from_clean_state():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    clean_generated_files()
    proc = run_build_script()
    assert proc.returncode == 0, f"build_and_test.sh failed:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"


def test_script_exists_and_executable():
    """Test if the bash script exists and is executable."""
    script_path = "/home/user/build_and_test.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_executable_compiled():
    """Test if the C program was compiled to the correct location."""
    exe_path = "/home/user/bin/math_check"
    assert os.path.isfile(exe_path), f"Compiled executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"Compiled file {exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled file {exe_path} is not an ELF executable."


def test_compiled_program_behavior():
    """Exercise the compiled artifact on values not present in the fixed fixture."""
    rng = random.SystemRandom()
    values = rng.sample(range(21, 151), 5)
    for n in values:
        assert decoded_result(n) == n * n + 15


def test_test_data_fixture():
    """Test if the test fixture file contains numbers 1 to 20."""
    data_path = "/home/user/test_data.txt"
    assert os.path.isfile(data_path), f"Test data file {data_path} does not exist."

    with open(data_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [str(i) for i in range(1, 21)]
    assert lines == expected_lines, f"Test data file {data_path} does not contain the expected integers 1 through 20."


def test_test_report_log():
    """Test if the test report log contains the correct PASS lines."""
    log_path = "/home/user/test_report.log"
    assert os.path.isfile(log_path), f"Test report log {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [f"[{i}] PASS" for i in range(1, 21)]
    assert lines == expected_lines, f"Test report log {log_path} does not contain the expected PASS lines."


def test_script_recompiles_source_and_detects_bad_results_and_failures():
    """Change the supplied source at runtime and verify true end-to-end orchestration."""
    rng = random.SystemRandom()
    wrong_n, error_n = rng.sample(range(1, 21), 2)

    with open(SOURCE, "rb") as f:
        original_source = f.read()

    probe_source = r'''#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int n = atoi(argv[1]);
    if (n == ERROR_N) return 9;
    volatile double exponent = 2.0;
    int val = (int)pow((double)n, exponent) + 15;
    if (n == WRONG_N) val += 1;
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "echo -n '%d' | base64", val);
    return system(cmd) == 0 ? 0 : 1;
}
'''.replace("WRONG_N", str(wrong_n)).replace("ERROR_N", str(error_n))

    try:
        with open(SOURCE, "w") as f:
            f.write(probe_source)

        clean_generated_files()
        proc = run_build_script()
        assert proc.returncode == 0, f"probe run failed:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"

        with open(EXE, "rb") as f:
            assert f.read(4) == b"\x7fELF", "The recreated math_check is not an ELF executable."

        assert decoded_result(wrong_n) == wrong_n * wrong_n + 16, \
            "math_check was not rebuilt from the current provided C source."
        failed_proc = subprocess.run([EXE, str(error_n)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        assert failed_proc.returncode != 0, "The rebuilt executable does not reflect the probe source."

        with open(DATA, "r") as f:
            data_lines = [line.strip() for line in f if line.strip()]
        assert data_lines == [str(i) for i in range(1, 21)]

        with open(LOG, "r") as f:
            report_lines = [line.strip() for line in f if line.strip()]
        expected = [
            f"[{i}] FAIL" if i in (wrong_n, error_n) else f"[{i}] PASS"
            for i in range(1, 21)
        ]
        assert report_lines == expected, \
            "The script did not execute, decode, validate, and log the probe program's results."
    finally:
        with open(SOURCE, "wb") as f:
            f.write(original_source)
        clean_generated_files()
        restored = run_build_script()
        assert restored.returncode == 0, \
            f"Failed to restore final outputs:\nstdout:\n{restored.stdout}\nstderr:\n{restored.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
