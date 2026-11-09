#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import pytest

SCRIPT_PATH = "/home/user/process_logs.sh"
LOG_FILE = "/home/user/iot_sensors.log"
ERROR_OUTPUT = "/home/user/error_summary.csv"
OK_OUTPUT = "/home/user/sampled_ok.log"


def get_expected_outputs(log_file=LOG_FILE):
    valid_regex = re.compile(r'^\[(\d{4}-\d{2}-\d{2}) (\d{2}):\d{2}:\d{2}\] \[SENS-\d{4}:([A-Z]+)\] (OK|ERROR) .+$')

    error_counts = {}
    ok_samples = []
    ok_counts = {}

    with open(log_file, 'r') as f:
        for line in f:
            line_stripped = line.strip('\n')
            match = valid_regex.match(line_stripped)
            if not match:
                continue
            date, hour, sens_type, status = match.groups()

            if status == 'ERROR':
                key = (date, hour, sens_type)
                error_counts[key] = error_counts.get(key, 0) + 1
            elif status == 'OK':
                ok_counts[sens_type] = ok_counts.get(sens_type, 0) + 1
                if ok_counts[sens_type] % 10 == 1:
                    ok_samples.append(line_stripped)

    expected_error_summary = []
    for (date, hour, sens_type), count in error_counts.items():
        expected_error_summary.append(f"{date},{hour},{sens_type},{count}")
    expected_error_summary.sort()

    return expected_error_summary, ok_samples


def read_nonempty_lines(path):
    with open(path, 'r') as f:
        return [line.strip('\n') for line in f if line.strip('\n')]


def run_script(input_path):
    for output in (ERROR_OUTPUT, OK_OUTPUT):
        try:
            os.remove(output)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [SCRIPT_PATH, input_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Script failed for input {input_path} with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


@pytest.fixture(scope="module")
def executed_original():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."
    run_script(LOG_FILE)


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_error_summary_csv(executed_original):
    output_file = ERROR_OUTPUT
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

    actual_lines = read_nonempty_lines(output_file)
    expected_error_summary, _ = get_expected_outputs()

    # The requirement says "sorted chronologically, then by Type", which matches a standard sort of the strings.
    # We sort the actual lines just in case, but we also assert it was already sorted.
    assert actual_lines == sorted(actual_lines), f"{output_file} is not sorted correctly."
    assert sorted(actual_lines) == expected_error_summary, f"Contents of {output_file} do not match the expected aggregated counts."


def test_sampled_ok_log(executed_original):
    output_file = OK_OUTPUT
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

    actual_lines = read_nonempty_lines(output_file)
    _, expected_ok_samples = get_expected_outputs()

    assert actual_lines == expected_ok_samples, f"Contents of {output_file} do not match the expected sampled OK logs."


def random_type():
    return ''.join(secrets.choice(string.ascii_uppercase) for _ in range(9))


def test_script_uses_first_argument_on_unseen_input(executed_original, tmp_path):
    first_type = random_type()
    second_type = random_type()
    while second_type == first_type:
        second_type = random_type()

    lines = []
    for i in range(11):
        lines.append(
            f"[2025-02-03 07:{i:02d}:10] [SENS-{2000 + i:04d}:{first_type}] OK first-{i}"
        )
        if i in (0, 4, 10):
            lines.append(
                f"[2025-02-03 08:{i:02d}:20] [SENS-{4000 + i:04d}:{second_type}] ERROR second-{i}"
            )

    lines.extend([
        f"[2025-02-04 01:00:00] [SENS-7777:{second_type}] OK alpha",
        f"[2025-02-04 01:00:01] [SENS-7778:{second_type}] OK beta",
        f"[2025-02-04 01:00:02] [SENS-7779:{first_type}] ERROR final",
        f"[2025-02-04 01:00:03] [SENS-12A3:{first_type}] OK malformed-id",
        f"[2025-02-04 01:00:04] [SENS-1234:{first_type.lower()}] OK malformed-type",
        f"2025-02-04 01:00:05 [SENS-1234:{first_type}] OK malformed-brackets",
        f"[2025-02-04 01:00:06] [SENS-1234:{first_type}] WARNING malformed-status",
    ])

    custom_log = tmp_path / ("unseen-" + secrets.token_hex(8) + ".log")
    custom_log.write_text('\n'.join(lines) + '\n')
    expected_errors, expected_samples = get_expected_outputs(str(custom_log))

    saved = {}
    for output in (ERROR_OUTPUT, OK_OUTPUT):
        if os.path.isfile(output):
            with open(output, 'rb') as f:
                saved[output] = f.read()

    try:
        run_script(str(custom_log))
        assert os.path.isfile(ERROR_OUTPUT), f"Output file {ERROR_OUTPUT} does not exist."
        assert os.path.isfile(OK_OUTPUT), f"Output file {OK_OUTPUT} does not exist."

        actual_errors = read_nonempty_lines(ERROR_OUTPUT)
        actual_samples = read_nonempty_lines(OK_OUTPUT)

        assert actual_errors == sorted(actual_errors), f"{ERROR_OUTPUT} is not sorted correctly."
        assert actual_errors == expected_errors, "Script did not aggregate the unseen first-argument input correctly."
        assert actual_samples == expected_samples, "Script did not sample the unseen first-argument input correctly."
    finally:
        for output, contents in saved.items():
            with open(output, 'wb') as f:
                f.write(contents)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
