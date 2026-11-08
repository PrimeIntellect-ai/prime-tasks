#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile


def test_valid_pin_file():
    """Verify the submitted PIN and confirm it is the unique PIN accepted by the source."""
    file_path = "/home/user/valid_pin.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == "4829", f"Expected valid_pin.txt to contain '4829', but got '{content}'."

    harness = r'''
#define main auth_logger_original_main
#include "/home/user/auth_system/auth_logger.cpp"
#undef main
#include <iostream>
int main() {
    for (int pin = 0; pin <= 9999; ++pin) {
        if (check_pin(pin)) std::cout << pin << "\n";
    }
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        harness_path = os.path.join(td, "pin_harness.cpp")
        binary_path = os.path.join(td, "pin_harness")
        with open(harness_path, "w") as f:
            f.write(harness)
        build = subprocess.run(
            ["g++", "-std=c++17", harness_path, "-o", binary_path],
            text=True, capture_output=True
        )
        assert build.returncode == 0, f"auth_logger.cpp failed to compile:\n{build.stderr}"
        run = subprocess.run([binary_path], text=True, capture_output=True)
        assert run.returncode == 0, f"PIN harness failed:\n{run.stderr}"
        accepted = [line.strip() for line in run.stdout.splitlines() if line.strip()]

    assert accepted == [content], (
        f"The source must accept exactly the submitted 4-digit PIN; accepted values were {accepted}."
    )


def test_cwe_id_file():
    """Verify that cwe_id.txt contains the correct CWE identifier."""
    file_path = "/home/user/cwe_id.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content.upper() == "CWE-532", f"Expected cwe_id.txt to contain 'CWE-532', but got '{content}'."


def test_redacted_logs_file():
    """Verify that redacted_logs.txt contains the correctly redacted logs."""
    file_path = "/home/user/redacted_logs.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    expected_logs = [
        "[INFO] System started at 08:00",
        "[INFO] User admin logged in",
        "[ERROR] Invalid attempt with PIN: ****",
        "[ERROR] Connection timeout from 192.168.1.50",
        "[ERROR] Invalid attempt with PIN: ****",
        "[ERROR] Invalid attempt with PIN: ****",
        "[INFO] Daily backup completed. PIN: 1234 was used for backup auth? No.",
        "[ERROR] Invalid attempt with PIN: ****"
    ]

    with open(file_path, "r") as f:
        actual_logs = [line.strip() for line in f.readlines() if line.strip()]

    assert len(actual_logs) == len(expected_logs), "The number of lines in redacted_logs.txt does not match the expected output."

    for i, (actual, expected) in enumerate(zip(actual_logs, expected_logs)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: '{expected}'\nGot: '{actual}'"


def test_redactor_cpp_exists():
    """Verify that the redactor.cpp source file was created."""
    file_path = "/home/user/redactor.cpp"
    assert os.path.isfile(file_path), f"File {file_path} is missing. You must write your C++ program to this location."


def test_redactor_cpp_compiles_and_processes_new_input():
    """Compile and execute the submitted redactor against independently checked cases."""
    source = "/home/user/redactor.cpp"
    input_path = "/home/user/auth_system/old_logs.txt"
    output_path = "/home/user/redacted_logs.txt"
    assert os.path.isfile(source), f"File {source} is missing."

    with tempfile.TemporaryDirectory() as td:
        binary = os.path.join(td, "redactor")
        build = subprocess.run(
            ["g++", "-std=c++17", source, "-o", binary],
            text=True, capture_output=True
        )
        assert build.returncode == 0, f"redactor.cpp failed to compile:\n{build.stderr}"

        lines = [
            "[ERROR] Invalid attempt with PIN: 0000",
            "[ERROR] Invalid attempt with PIN: 7301",
            "prefix [ERROR] Invalid attempt with PIN: 2468",
            "[ERROR] Invalid attempt with PIN: 12345",
            "[ERROR] Invalid attempt with PIN: 12a4",
            "[INFO] PIN 9876 must remain visible here",
            "[ERROR] Invalid attempt with PIN: 9999 trailing text",
            "ordinary number 4321"
        ]
        matcher = re.compile(r"^\[ERROR\] Invalid attempt with PIN: (\d{4})$")
        expected_lines = [
            "[ERROR] Invalid attempt with PIN: ****" if matcher.fullmatch(line) else line
            for line in lines
        ]
        test_input = "\n".join(lines) + "\n"
        expected = "\n".join(expected_lines) + "\n"

        with open(input_path, "rb") as f:
            original_input = f.read()
        original_output = None
        if os.path.exists(output_path):
            with open(output_path, "rb") as f:
                original_output = f.read()

        try:
            with open(input_path, "w") as f:
                f.write(test_input)
            if os.path.exists(output_path):
                os.remove(output_path)

            run = subprocess.run([binary], cwd="/home/user", text=True, capture_output=True)
            assert run.returncode == 0, f"Compiled redactor failed:\n{run.stderr}"

            if os.path.isfile(output_path):
                with open(output_path, "r") as f:
                    actual = f.read()
            else:
                actual = run.stdout
            assert actual == expected, f"Redactor produced incorrect output.\nExpected:\n{expected}\nGot:\n{actual}"
        finally:
            with open(input_path, "wb") as f:
                f.write(original_input)
            if original_output is None:
                if os.path.exists(output_path):
                    os.remove(output_path)
            else:
                with open(output_path, "wb") as f:
                    f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
