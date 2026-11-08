#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import stat
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path("/home/user/run_mc.sh")
SOURCE = Path("/home/user/inv.cpp")
EXE = Path("/home/user/inv")
RESULT = Path("/home/user/result.txt")
VALUES = ["1", "0.1", "0.01", "0.001", "0.0001"]

EXPECTED_SOURCE = '''#include <iostream>
#include <cstdlib>

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    double epsilon = std::atof(argv[1]);
    // Matrix A:
    // [ 1.0 , 1.0 ]
    // [ 1.0 , 1.0 + epsilon ]
    double a = 1.0, b = 1.0, c = 1.0, d = 1.0 + epsilon;
    double det = a*d - b*c;
    if (det == 0) {
        std::cout << "NaN" << std::endl;
        return 1;
    }
    double inv_a = d / det;
    std::cout << inv_a << std::endl;
    return 0;
}
'''

PROBE_SOURCE = r'''#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iostream>

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    std::ofstream log("/tmp/run_mc_invocations.log", std::ios::app);
    log << argv[1] << "\n";
    double epsilon = std::atof(argv[1]);
    if (std::fabs(epsilon - 0.1) < 1e-12) {
        std::cout << 1500.0 << std::endl;
    } else if (std::fabs(epsilon - 0.01) < 1e-12) {
        std::cout << 1200.0 << std::endl;
    } else {
        std::cout << 5.0 << std::endl;
    }
    return 0;
}
'''


def remove_outputs():
    for path in (EXE, RESULT):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def run_script():
    completed = subprocess.run(
        [str(SCRIPT)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"run_mc.sh failed with exit code {completed.returncode}. "
        f"stdout={completed.stdout!r}, stderr={completed.stderr!r}"
    )


def assert_elf_executable():
    assert EXE.is_file(), "run_mc.sh did not create /home/user/inv"
    assert os.access(EXE, os.X_OK), "/home/user/inv is not executable"
    with EXE.open("rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/inv is not a compiled ELF executable"


def read_result():
    assert RESULT.is_file(), "run_mc.sh did not create /home/user/result.txt"
    return RESULT.read_text().strip()


def test_script_compiles_executes_and_searches():
    assert SCRIPT.is_file(), f"Script {SCRIPT} does not exist."
    assert os.stat(SCRIPT).st_mode & stat.S_IXUSR, f"Script {SCRIPT} is not executable."
    assert SOURCE.read_text() == EXPECTED_SOURCE, "/home/user/inv.cpp was modified"

    # Run from a clean state and check the real supplied implementation.
    remove_outputs()
    run_script()
    assert_elf_executable()

    observed = []
    for epsilon_text in VALUES:
        completed = subprocess.run(
            [str(EXE), epsilon_text],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
        assert completed.returncode == 0
        value = float(completed.stdout.strip())
        epsilon = float(epsilon_text)
        assert math.isclose(value, (1.0 + epsilon) / epsilon, rel_tol=2e-5, abs_tol=1e-5)
        observed.append((epsilon, epsilon_text, value))

    qualifying = [entry for entry in observed if entry[2] > 1000.0]
    expected_result = max(qualifying, key=lambda entry: entry[0])[1]
    assert read_result() == expected_result

    # Replace the source temporarily with an instrumented implementation. This
    # proves the script recompiles inv.cpp, invokes inv for every listed value,
    # and derives the largest qualifying epsilon rather than hardcoding 0.001.
    original_bytes = SOURCE.read_bytes()
    original_mode = stat.S_IMODE(os.stat(SOURCE).st_mode)
    log_path = Path("/tmp/run_mc_invocations.log")
    try:
        SOURCE.write_text(PROBE_SOURCE)
        os.chmod(SOURCE, original_mode)
        try:
            log_path.unlink()
        except FileNotFoundError:
            pass
        remove_outputs()
        run_script()
        assert_elf_executable()
        assert read_result() == "0.1", "run_mc.sh did not derive the result from executable output"
        assert log_path.is_file(), "The compiled probe executable was never run"
        arguments = [line.strip() for line in log_path.read_text().splitlines() if line.strip()]
        assert len(arguments) == len(VALUES), f"Expected one invocation per epsilon, got {arguments!r}"
        assert [float(value) for value in arguments] == [float(value) for value in VALUES], (
            f"Expected decreasing epsilon sequence {VALUES!r}, got {arguments!r}"
        )
    finally:
        SOURCE.write_bytes(original_bytes)
        os.chmod(SOURCE, original_mode)

    # Leave and verify the requested final state using the real source.
    remove_outputs()
    run_script()
    assert_elf_executable()


def test_run_mc_script_exists_and_executable():
    script_path = "/home/user/run_mc.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_inv_executable_exists():
    exe_path = "/home/user/inv"
    assert os.path.isfile(exe_path), f"Compiled executable {exe_path} does not exist. Did the script compile it?"
    st = os.stat(exe_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Compiled file {exe_path} is not executable."


def test_result_file_content():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"Result file {result_path} does not exist."

    with open(result_path, "r") as f:
        content = f.read().strip()

    assert content == "0.001", f"Expected result file to contain '0.001', but found '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
