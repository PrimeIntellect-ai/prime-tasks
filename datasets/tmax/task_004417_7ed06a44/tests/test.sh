#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest


def run_handler(path, argument):
    return subprocess.run(
        [path, argument], capture_output=True, text=True, timeout=5
    )


def test_upload_handler_executable_exists():
    path = "/home/user/upload_handler"
    assert os.path.isfile(path), f"Executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_upload_handler_malicious_input():
    path = "/home/user/upload_handler"

    # Test with "../"
    result = subprocess.run([path, "../malicious.txt"], capture_output=True, text=True)
    assert result.returncode == 1, f"Expected exit code 1 for malicious input '../', got {result.returncode}"
    assert result.stdout == "ERR: Invalid filename\n", f"Expected exact stdout 'ERR: Invalid filename\\n' for '../', got {repr(result.stdout)}"

    # Test with "/"
    result2 = subprocess.run([path, "folder/file.txt"], capture_output=True, text=True)
    assert result2.returncode == 1, f"Expected exit code 1 for malicious input with '/', got {result2.returncode}"
    assert result2.stdout == "ERR: Invalid filename\n", f"Expected exact stdout 'ERR: Invalid filename\\n' for '/', got {repr(result2.stdout)}"


def test_upload_handler_safe_input():
    path = "/home/user/upload_handler"
    safe_filename = "safe_test_file.txt"
    expected_out_path = f"/home/user/uploads/{safe_filename}"

    if os.path.exists(expected_out_path):
        os.remove(expected_out_path)

    result = subprocess.run([path, safe_filename], capture_output=True, text=True)
    assert result.returncode == 0, f"Expected exit code 0 for safe input, got {result.returncode}. stderr: {result.stderr}"
    assert os.path.isfile(expected_out_path), f"Expected file {expected_out_path} to be created for safe input."


def test_source_compiles_and_policy_is_enforced_generally():
    source = "/home/user/upload_handler.c"
    submitted = "/home/user/upload_handler"
    assert os.path.isfile(source), f"Source file {source} does not exist."

    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt = os.path.join(temp_dir, "upload_handler_rebuilt")
        compilation = subprocess.run(
            ["gcc", source, "-o", rebuilt], capture_output=True, text=True, timeout=20
        )
        assert compilation.returncode == 0, (
            "The remediated C source does not compile with the required command.\n"
            f"stdout: {compilation.stdout}\nstderr: {compilation.stderr}"
        )

        # Exercise both the submitted executable and an independently compiled copy
        # using unpredictable filenames, so fixed argument special-casing cannot pass.
        for executable in (submitted, rebuilt):
            for _ in range(6):
                token = secrets.token_hex(10)

                safe_name = f"safe_{token}.dat"
                safe_path = os.path.join("/home/user/uploads", safe_name)
                if os.path.exists(safe_path):
                    os.remove(safe_path)
                safe_result = run_handler(executable, safe_name)
                assert safe_result.returncode == 0, (
                    f"Expected success for slash-free filename {safe_name!r}, "
                    f"got {safe_result.returncode}; stderr: {safe_result.stderr!r}"
                )
                assert os.path.isfile(safe_path), (
                    f"Expected {safe_path} to be created for a safe filename."
                )
                os.remove(safe_path)

                nested_dir_name = f"nested_{token}"
                nested_dir = os.path.join("/home/user/uploads", nested_dir_name)
                os.makedirs(nested_dir, exist_ok=True)
                nested_target = os.path.join(nested_dir, f"file_{token}.txt")
                invalid_nested = f"{nested_dir_name}/file_{token}.txt"
                nested_result = run_handler(executable, invalid_nested)
                assert nested_result.returncode == 1, (
                    f"Expected exit code 1 for filename {invalid_nested!r}, "
                    f"got {nested_result.returncode}"
                )
                assert nested_result.stdout == "ERR: Invalid filename\n", (
                    f"Expected exact invalid-filename message for {invalid_nested!r}, "
                    f"got {nested_result.stdout!r}"
                )
                assert not os.path.exists(nested_target), (
                    "Handler performed a file operation for a filename containing '/'."
                )
                os.rmdir(nested_dir)

                outside_name = f"outside_{token}.txt"
                outside_path = os.path.join("/home/user", outside_name)
                if os.path.exists(outside_path):
                    os.remove(outside_path)
                invalid_parent = f"../{outside_name}"
                parent_result = run_handler(executable, invalid_parent)
                assert parent_result.returncode == 1, (
                    f"Expected exit code 1 for filename {invalid_parent!r}, "
                    f"got {parent_result.returncode}"
                )
                assert parent_result.stdout == "ERR: Invalid filename\n", (
                    f"Expected exact invalid-filename message for {invalid_parent!r}, "
                    f"got {parent_result.stdout!r}"
                )
                assert not os.path.exists(outside_path), (
                    "Handler created a file for a parent-directory traversal filename."
                )


def test_redacted_alerts_log():
    traffic_log = "/home/user/traffic.log"
    redacted_log = "/home/user/redacted_alerts.log"

    assert os.path.isfile(traffic_log), f"{traffic_log} is missing."
    assert os.path.isfile(redacted_log), f"{redacted_log} is missing."

    with open(traffic_log, "r") as f:
        traffic_lines = f.read().splitlines()

    expected_redacted = []
    for line in traffic_lines:
        if "FILE: " in line:
            parts = line.split("FILE: ")
            if len(parts) > 1:
                file_part = parts[1].split(" ")[0]
                if "../" in file_part or "/" in file_part:
                    if " KEY: " in line:
                        prefix, key_val = line.split(" KEY: ", 1)
                        expected_redacted.append(f"{prefix} KEY: [REDACTED]")

    with open(redacted_log, "r") as f:
        actual_redacted = f.read().splitlines()

    assert actual_redacted == expected_redacted, (
        "The contents of redacted_alerts.log do not match the expected redacted malicious records.\n"
        f"Expected:\n{expected_redacted}\nGot:\n{actual_redacted}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
