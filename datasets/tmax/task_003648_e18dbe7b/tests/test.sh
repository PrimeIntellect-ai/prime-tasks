#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest


def deleted_upstream_contents():
    candidates = []
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        try:
            with open(f'/proc/{pid}/cmdline', 'rb') as f:
                cmdline = f.read().split(b'\0')
            if not any(arg.endswith(b'upstream_service.py') for arg in cmdline):
                continue
            fd_dir = f'/proc/{pid}/fd'
            for fd in os.listdir(fd_dir):
                fd_path = os.path.join(fd_dir, fd)
                try:
                    target = os.readlink(fd_path)
                    if target.endswith('/data.csv (deleted)'):
                        with open(fd_path, 'rb') as f:
                            candidates.append(f.read())
                except (FileNotFoundError, PermissionError, OSError):
                    pass
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            pass
    assert candidates, 'Could not find the deleted data.csv held open by upstream_service.py'
    return candidates


def test_recovered_data_csv():
    path = "/home/user/recovered_data.csv"
    assert os.path.isfile(path), f"File {path} does not exist. Did you recover the deleted file?"

    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 1000, f"Expected 1000 lines in {path}, found {len(lines)}"

    count_10 = lines.count("10")
    count_neg1 = lines.count("-1")

    assert count_10 == 999, f"Expected 999 occurrences of '10' in {path}, found {count_10}"
    assert count_neg1 == 1, f"Expected 1 occurrence of '-1' in {path}, found {count_neg1}"

    with open(path, 'rb') as f:
        recovered = f.read()
    originals = deleted_upstream_contents()
    assert recovered in originals, (
        'recovered_data.csv does not exactly match the deleted file still held open '
        'by upstream_service.py (including ordering and line endings)'
    )


def test_summary_report_txt():
    path = "/home/user/summary_report.txt"
    assert os.path.isfile(path), f"File {path} does not exist. Did you run the script and redirect output?"

    with open(path, 'r') as f:
        content = f.read().strip()

    assert content == "10: 999", f"Expected summary report to contain exactly '10: 999', but found: '{content}'"


def test_process_data_script_fixed():
    script_path = "/home/user/data_pipeline/process_data.sh"
    data_path = "/home/user/recovered_data.csv"

    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    try:
        result = subprocess.run([script_path, data_path], capture_output=True, text=True, check=True, timeout=10)
        output = result.stdout.strip()
        assert output == "10: 999", f"Expected script output to be '10: 999', but got: '{output}'"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script crashed or returned non-zero exit code when run on recovered data. Error: {e.stderr}")


def parse_tallies(output):
    tallies = {}
    for line in output.splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r'([0-9]+): ([0-9]+)', line.strip())
        assert match, f"Malformed tally output line: {line!r}"
        value, count = map(int, match.groups())
        assert value not in tallies, f"Duplicate tally for value {value}"
        tallies[value] = count
    return tallies


def run_case(values):
    script_path = "/home/user/data_pipeline/process_data.sh"
    expected = {}
    for value in values:
        if value >= 0:
            expected[value] = expected.get(value, 0) + 1

    fd, path = tempfile.mkstemp(prefix='pipeline-input-', suffix='.csv')
    try:
        with os.fdopen(fd, 'w') as f:
            for value in values:
                f.write(f'{value}\n')
        result = subprocess.run(
            [script_path, path], capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, (
            f"Script failed on valid numerical input containing negatives: {result.stderr}"
        )
        assert parse_tallies(result.stdout) == expected
    finally:
        os.unlink(path)


def test_process_data_handles_general_negative_inputs():
    run_case([-1, -7, -2])
    run_case([3, -1, 3, 0, -9, 2, 0, 11, -3])

    rng = secrets.SystemRandom()
    for _ in range(6):
        values = [rng.randrange(0, 80) for _ in range(rng.randrange(20, 60))]
        values += [-rng.randrange(1, 80) for _ in range(rng.randrange(5, 20))]
        rng.shuffle(values)
        run_case(values)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
