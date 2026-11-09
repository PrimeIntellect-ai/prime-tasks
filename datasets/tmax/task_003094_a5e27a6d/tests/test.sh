#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest

CPP_PATH = "/home/user/generate_report.cpp"
REPORT_PATH = "/home/user/report.txt"
GENERATOR_PATH = "/tmp/generate_report_verifier"


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_generator():
    assert os.path.isfile(CPP_PATH), f"The C++ source file {CPP_PATH} does not exist."

    compile_result = subprocess.run(
        ["g++", "-std=c++17", CPP_PATH, "-o", GENERATOR_PATH],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "generate_report.cpp failed to compile:\n"
        + compile_result.stdout
        + compile_result.stderr
    )

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    first_run = subprocess.run(
        [GENERATOR_PATH], cwd="/home/user", capture_output=True, text=True, timeout=30
    )
    assert first_run.returncode == 0, (
        f"The compiled generator exited with code {first_run.returncode}.\n"
        + first_run.stdout
        + first_run.stderr
    )
    assert os.path.isfile(REPORT_PATH), "The compiled generator did not create /home/user/report.txt."

    with open(REPORT_PATH, "rb") as f:
        first_report = f.read()

    os.remove(REPORT_PATH)
    second_run = subprocess.run(
        [GENERATOR_PATH], cwd="/home/user", capture_output=True, text=True, timeout=30
    )
    assert second_run.returncode == 0, (
        f"The compiled generator exited with code {second_run.returncode} on its second run.\n"
        + second_run.stdout
        + second_run.stderr
    )
    assert os.path.isfile(REPORT_PATH), "The compiled generator did not recreate /home/user/report.txt."

    with open(REPORT_PATH, "rb") as f:
        second_report = f.read()

    assert first_report == second_report, "The generator did not produce deterministic report output."


def test_generate_report_cpp_exists():
    cpp_path = "/home/user/generate_report.cpp"
    assert os.path.isfile(cpp_path), f"The C++ source file {cpp_path} does not exist."


def test_report_txt_exists_and_format():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"The report file {report_path} does not exist."

    token = None
    backdoor = None

    with open(report_path, "r") as f:
        for line in f:
            if line.startswith("TOKEN:"):
                token = line.split("TOKEN:", 1)[1].strip()
            elif line.startswith("BACKDOOR:"):
                backdoor = line.split("BACKDOOR:", 1)[1].strip()

    assert token is not None, "The report.txt file is missing the 'TOKEN:' line."
    assert backdoor is not None, "The report.txt file is missing the 'BACKDOOR:' line."

    assert backdoor == "admin' OR 1=1 --", f"The backdoor payload is incorrect. Found: {backdoor}"


def test_token_and_payload_with_binary():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"The report file {report_path} does not exist."

    token = None
    backdoor = None

    with open(report_path, "r") as f:
        for line in f:
            if line.startswith("TOKEN:"):
                token = line.split("TOKEN:", 1)[1].strip()
            elif line.startswith("BACKDOOR:"):
                backdoor = line.split("BACKDOOR:", 1)[1].strip()

    assert token is not None, "Could not parse TOKEN from report.txt."
    assert backdoor is not None, "Could not parse BACKDOOR from report.txt."

    binary_path = "/home/user/traffic_analyzer"
    assert os.path.isfile(binary_path), f"The binary {binary_path} is missing."
    assert os.access(binary_path, os.X_OK), f"The binary {binary_path} is not executable."

    result = subprocess.run([binary_path, token, backdoor], capture_output=True)

    # Exit code 2: Invalid length
    # Exit code 3: Invalid prefix
    # Exit code 4: Invalid checksum
    # Exit code 5: Invalid payload
    # Exit code 42: Success
    assert result.returncode == 42, f"The binary rejected the token and payload. Expected exit code 42, got {result.returncode}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
