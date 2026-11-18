#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess

LOG_PATH = "/home/user/system_metrics.log"
AWK_PATH = "/home/user/calculate_cooling.awk"
REPORT_PATH = "/home/user/fixed_report.txt"

EXPECTED_LOG_LINES = [
    "1700000000 45 3000",
    "1700000010 50 3300",
    "1700000020 40 2000",
    "1700000030 20 1500",
    "1700000040 25 1000",
    "1700000050 15 800",
    "1700000060 60 4000",
]

EXPECTED_REPORT_LINES = [
    "1700000000 120",
    "1700000010 110",
    "1700000020 100",
    "1700000030 0",
    "1700000040 200",
    "1700000050 0",
    "1700000060 100",
]


def nonempty_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def run_awk(input_text=None, input_path=None):
    command = ["awk", "-f", AWK_PATH]
    if input_path is not None:
        command.append(input_path)
        result = subprocess.run(command, text=True, capture_output=True, timeout=10)
    else:
        result = subprocess.run(
            command, input=input_text, text=True, capture_output=True, timeout=10
        )
    assert result.returncode == 0, (
        f"The awk script failed with exit code {result.returncode}: {result.stderr}"
    )
    return nonempty_lines(result.stdout)


def test_log_was_deduplicated_in_first_occurrence_order():
    assert os.path.isfile(LOG_PATH), f"The log file {LOG_PATH} is missing."
    with open(LOG_PATH, "r") as f:
        actual_lines = nonempty_lines(f.read())
    assert actual_lines == EXPECTED_LOG_LINES, (
        "system_metrics.log was not deduplicated while preserving the original "
        "order of each line's first occurrence."
    )


def test_fixed_report_exists_and_correct():
    assert os.path.isfile(REPORT_PATH), f"The final report file {REPORT_PATH} does not exist."

    with open(REPORT_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = EXPECTED_REPORT_LINES
    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in the report, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        actual_parts = actual.split()
        expected_parts = expected.split()
        assert actual_parts == expected_parts, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."


def test_awk_script_modified():
    assert os.path.isfile(AWK_PATH), f"The script {AWK_PATH} is missing."
    assert not os.path.islink(AWK_PATH), f"The script {AWK_PATH} must be a regular file, not a symbolic link."
    assert stat.S_ISREG(os.stat(AWK_PATH).st_mode), f"The script {AWK_PATH} is not a regular file."

    with open(AWK_PATH, "r") as f:
        content = f.read()

    # Preserve the original source-level assertion.
    assert "20" in content, "The awk script does not seem to contain the threshold value 20."


def test_report_is_actual_output_of_script_on_clean_log():
    actual_output = run_awk(input_path=LOG_PATH)
    with open(REPORT_PATH, "r") as f:
        saved_output = nonempty_lines(f.read())
    assert actual_output == saved_output, (
        "fixed_report.txt is not the output produced by calculate_cooling.awk "
        "when run on the deduplicated system_metrics.log."
    )


def test_awk_formula_and_edge_condition_on_fresh_inputs():
    # Values are generated only after the agent has finished, so the script must
    # implement the requested formula rather than recognize the shipped log.
    base_timestamp = 1800000000 + secrets.randbelow(10000000)
    cases = []

    for offset, temperature in enumerate((20, 19, 0, -5)):
        rpm = 1 + secrets.randbelow(9000)
        cases.append((base_timestamp + offset, temperature, rpm, 0.0))

    for offset in range(4, 10):
        denominator = 1 + secrets.randbelow(80)
        factor = 1 + secrets.randbelow(300)
        temperature = 20 + denominator
        rpm = denominator * factor
        cases.append((base_timestamp + offset, temperature, rpm, float(factor)))

    input_text = "".join(f"{ts} {temp} {rpm}\n" for ts, temp, rpm, _ in cases)
    output = run_awk(input_text=input_text)
    assert len(output) == len(cases), (
        f"Expected one output line per input line ({len(cases)}), got {len(output)}."
    )

    for index, (line, (timestamp, _, _, expected_factor)) in enumerate(zip(output, cases), 1):
        fields = line.split()
        assert len(fields) == 2, f"Output line {index} must contain timestamp and cooling factor: {line!r}"
        assert fields[0] == str(timestamp), (
            f"Output line {index} changed or omitted the input timestamp."
        )
        try:
            actual_factor = float(fields[1])
        except ValueError:
            raise AssertionError(f"Output line {index} has a non-numeric cooling factor: {fields[1]!r}")
        assert actual_factor == expected_factor, (
            f"Wrong cooling factor on fresh case {index}: expected {expected_factor:g}, "
            f"got {fields[1]}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
