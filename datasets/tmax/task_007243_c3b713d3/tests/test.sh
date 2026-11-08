#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import statistics
import subprocess

RESULT_PATH = "/home/user/result.txt"
GO_FILE = "/home/user/log_analyzer.go"
DATA_FILE = "/home/user/network_data.txt"


def run_analyzer():
    proc = subprocess.run(
        ["go", "run", GO_FILE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        env={**os.environ, "GO111MODULE": "off"},
    )
    assert proc.returncode == 0, (
        f"Analyzer failed with exit code {proc.returncode}. stderr: {proc.stderr}"
    )
    return proc.stdout


def test_result_file_exists_and_correct():
    assert os.path.isfile(RESULT_PATH), f"File {RESULT_PATH} is missing."

    with open(RESULT_PATH, "r") as f:
        content = f.read()

    expected = "0.0816"
    assert content.strip() == expected, (
        f"Expected content '{expected}', but got '{content.strip()}'"
    )
    assert content.endswith("\n"), f"File {RESULT_PATH} must have a trailing newline."


def test_log_analyzer_fixed():
    assert os.path.isfile(GO_FILE), f"File {GO_FILE} is missing."

    with open(GO_FILE, "r") as f:
        content = f.read()

    assert "float64" in content, (
        "The script does not seem to have been upgraded to use float64."
    )
    assert "float32" not in content, (
        "The script still contains float32 types, which cause precision loss."
    )

    with open(RESULT_PATH, "r") as f:
        saved_result = f.read()

    # Confirm the submitted result is exactly what the analyzer emits for the
    # recovered dataset, rather than merely a hardcoded result file.
    assert run_analyzer() == saved_result, (
        "result.txt does not exactly match the analyzer's output for network_data.txt"
    )

    with open(DATA_FILE, "rb") as f:
        original_data = f.read()

    rng = secrets.SystemRandom()
    try:
        # Exercise the analyzer on verifier-generated datasets so a fixed output
        # or implementation specialized to the recovered three values cannot pass.
        for _ in range(3):
            base = rng.randrange(100, 901)
            offsets = rng.sample(range(-900, 901), 7)
            values = [base + offset / 1000.0 for offset in offsets]
            data = "".join(f"{value:.3f}\n" for value in values)

            with open(DATA_FILE, "w") as f:
                f.write(data)

            parsed_values = [float(line) for line in data.splitlines()]
            expected_output = f"{statistics.pstdev(parsed_values):.4f}\n"
            actual_output = run_analyzer()
            assert actual_output == expected_output, (
                f"For generated input {parsed_values}, expected "
                f"{expected_output!r}, got {actual_output!r}"
            )
    finally:
        with open(DATA_FILE, "wb") as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
