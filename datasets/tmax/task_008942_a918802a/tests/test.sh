#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess

EXPECTED_OUTPUT = (
    "Sum: 150\n"
    "Root 0: 3.162\n"
    "Root 1: 4.472\n"
    "Root 2: 5.477\n"
    "Root 3: 6.325\n"
    "Root 4: 7.071\n"
)


def run_program(path, timeout=5):
    result = subprocess.run(
        [path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}.\n"
        f"stderr:\n{result.stderr}"
    )
    return result.stdout


def test_calibrator_c_exists():
    filepath = "/home/user/calibrator.c"
    assert os.path.isfile(filepath), f"File {filepath} does not exist. The source code must be preserved."


def test_calibrator_executable_exists():
    filepath = "/home/user/calibrator"
    assert os.path.isfile(filepath), f"Executable {filepath} does not exist. Did you compile the program?"
    assert os.access(filepath, os.X_OK), f"File {filepath} is not executable."
    with open(filepath, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {filepath} is not a compiled ELF executable."


def test_calibration_output_correct():
    filepath = "/home/user/calibration_output.txt"
    assert os.path.isfile(filepath), f"Output file {filepath} does not exist. Did you run the program and redirect output?"

    with open(filepath, "r") as f:
        actual_output = f.read()

    assert actual_output.strip() == EXPECTED_OUTPUT.strip(), (
        f"Contents of {filepath} do not match the expected output.\n"
        f"Expected:\n{EXPECTED_OUTPUT}\n"
        f"Actual:\n{actual_output}"
    )


def test_submitted_executable_runs_correctly():
    actual_output = run_program("/home/user/calibrator")
    assert actual_output.strip() == EXPECTED_OUTPUT.strip(), (
        "The submitted executable does not produce the required output when run.\n"
        f"Expected:\n{EXPECTED_OUTPUT}\nActual:\n{actual_output}"
    )


def test_fixed_source_compiles_and_runs_without_undefined_behavior():
    rebuilt = "/tmp/calibrator_rebuilt"
    checked = "/tmp/calibrator_checked"

    compile_result = subprocess.run(
        ["gcc", "-o", rebuilt, "/home/user/calibrator.c", "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compile_result.returncode == 0, f"The submitted source does not compile:\n{compile_result.stderr}"

    rebuilt_output = run_program(rebuilt)
    assert rebuilt_output.strip() == EXPECTED_OUTPUT.strip(), (
        "A fresh build of calibrator.c does not produce the required output.\n"
        f"Expected:\n{EXPECTED_OUTPUT}\nActual:\n{rebuilt_output}"
    )

    with open("/home/user/calibrator", "rb") as submitted_file, open(rebuilt, "rb") as rebuilt_file:
        assert submitted_file.read() == rebuilt_file.read(), (
            "/home/user/calibrator is not the executable produced by compiling the submitted calibrator.c "
            "with the required gcc command."
        )

    checked_compile = subprocess.run(
        [
            "gcc", "-O0", "-fsanitize=undefined,bounds",
            "-fno-sanitize-recover=all", "-o", checked,
            "/home/user/calibrator.c", "-lm"
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert checked_compile.returncode == 0, (
        f"The source could not be compiled with runtime checks enabled:\n{checked_compile.stderr}"
    )

    checked_output = run_program(checked)
    assert checked_output.strip() == EXPECTED_OUTPUT.strip(), (
        "The checked build does not produce the required output.\n"
        f"Expected:\n{EXPECTED_OUTPUT}\nActual:\n{checked_output}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
