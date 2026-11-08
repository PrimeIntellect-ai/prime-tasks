#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile

REPORT_PATH = "/home/user/investigation_report.txt"
TARGET_FILE_PATH = "/home/user/.conf_7781a"
C_FILE_PATH = "/home/user/malware.c"
PCAP_PORT = "8443"


def compute_expected_hex(data: str) -> str:
    """Derives the expected hex output based on the malware's encoding logic."""
    fib = [1, 1]
    for i in range(2, 10):
        fib.append(fib[i - 1] + fib[i - 2])

    encoded_chars = []
    for i, char in enumerate(data):
        encoded_val = (ord(char) + fib[i % 10]) & 0xFF
        encoded_chars.append(f"{encoded_val:02x}")
    return "".join(encoded_chars)


def test_investigation_report_exists():
    assert os.path.isfile(REPORT_PATH), (
        f"The investigation report file is missing at {REPORT_PATH}."
    )


def test_investigation_report_contents():
    with open(REPORT_PATH, "r") as f:
        lines = [line.strip() for line in f.read().strip().split("\n")]

    assert len(lines) == 3, (
        f"Expected exactly 3 lines in {REPORT_PATH}, but found {len(lines)}."
    )
    assert lines[0] == TARGET_FILE_PATH, (
        "Line 1 of the report is incorrect. Expected the absolute path of the "
        f"hidden file, got: '{lines[0]}'"
    )
    assert lines[1] == PCAP_PORT, (
        "Line 2 of the report is incorrect. Expected the destination TCP port, "
        f"got: '{lines[1]}'"
    )

    assert os.path.isfile(TARGET_FILE_PATH), (
        f"Target file {TARGET_FILE_PATH} is missing, cannot verify hex output."
    )
    with open(TARGET_FILE_PATH, "r") as f:
        target_data = f.read()

    expected_hex = compute_expected_hex(target_data)
    assert lines[2] == expected_hex, (
        "Line 3 of the report is incorrect. Expected the hex output of the "
        f"repaired malware, got: '{lines[2]}'"
    )


def test_malware_c_fixed_and_executable():
    assert os.path.isfile(C_FILE_PATH), f"The source file {C_FILE_PATH} is missing."

    with open(TARGET_FILE_PATH, "r") as f:
        target_data = f.read()
    expected_output = compute_expected_hex(target_data) + "\n"

    with tempfile.TemporaryDirectory() as temp_dir:
        binary_path = os.path.join(temp_dir, "malware_rebuilt")
        compile_result = subprocess.run(
            [
                "gcc",
                "-O0",
                "-g",
                "-fsanitize=address",
                "-fno-omit-frame-pointer",
                C_FILE_PATH,
                "-o",
                binary_path,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "The repaired malware source could not be recompiled:\n"
            + compile_result.stderr
        )
        assert os.path.isfile(binary_path) and os.access(binary_path, os.X_OK), (
            "Recompilation did not produce an executable malware binary."
        )

        run_result = subprocess.run(
            [binary_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert run_result.returncode == 0, (
            "The rebuilt malware did not execute successfully; the boundary error "
            "may still be present.\n" + run_result.stderr
        )
        assert run_result.stdout == expected_output, (
            "The rebuilt malware produced incorrect output. "
            f"Expected {expected_output!r}, got {run_result.stdout!r}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
