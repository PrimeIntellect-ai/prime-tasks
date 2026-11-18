#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import shutil
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/tracker.sh"
MANIFEST_PATH = "/home/user/deploy.json"
CSV_PATH = "/home/user/elf_deps.csv"


def get_interpreter(binary_path):
    try:
        output = subprocess.check_output(
            ["readelf", "-l", binary_path], stderr=subprocess.DEVNULL
        ).decode("utf-8")
        for line in output.splitlines():
            if "program interpreter" in line:
                parts = line.split(":")
                if len(parts) > 1:
                    return parts[1].strip().strip("]")
    except Exception:
        pass
    return None


def read_csv():
    with open(CSV_PATH, "r", newline="") as f:
        return [row for row in csv.reader(f) if row]


def tool_was_executed(trace, tool):
    pattern = re.compile(r"(?:^|[\s/])" + re.escape(tool) + r"(?=\s|$)")
    return any(pattern.search(line) for line in trace.splitlines())


def run_tracker():
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        ["bash", "-x", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        env={**os.environ, "LC_ALL": "C"},
    )
    assert result.returncode == 0, (
        f"tracker.sh failed with exit code {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    assert os.path.isfile(CSV_PATH), f"The output CSV file {CSV_PATH} was not created."
    assert tool_was_executed(result.stderr, "jq"), "tracker.sh did not execute jq."
    assert tool_was_executed(result.stderr, "readelf"), "tracker.sh did not execute readelf."


@pytest.fixture(scope="session", autouse=True)
def execute_original_script():
    assert os.path.isfile(SCRIPT_PATH), f"The Bash script {SCRIPT_PATH} was not created."
    syntax = subprocess.run(
        ["bash", "-n", SCRIPT_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert syntax.returncode == 0, f"tracker.sh is not valid Bash: {syntax.stderr}"
    run_tracker()


def test_csv_exists():
    assert os.path.isfile(CSV_PATH), f"The output CSV file {CSV_PATH} was not created."


def test_csv_content():
    assert os.path.isfile(CSV_PATH), "CSV file missing."

    ls_interp = get_interpreter("/bin/ls")
    cat_interp = get_interpreter("/bin/cat")

    assert ls_interp is not None, "Could not determine interpreter for /bin/ls"
    assert cat_interp is not None, "Could not determine interpreter for /bin/cat"

    expected_rows = [
        ["job-101", "/home/user/bin/app_ls", ls_interp],
        ["job-103", "/home/user/bin/app_cat", cat_interp],
    ]

    actual_rows = read_csv()
    assert len(actual_rows) == 2, (
        f"Expected exactly 2 lines in the CSV, but found {len(actual_rows)}."
    )
    for expected_row in expected_rows:
        assert expected_row in actual_rows, (
            f"Expected row {expected_row} not found in the CSV. "
            f"Actual contents: {actual_rows}"
        )


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The Bash script {SCRIPT_PATH} was not created."


def test_tracker_processes_unseen_manifest():
    with open(MANIFEST_PATH, "rb") as f:
        original_manifest = f.read()

    fixture_dir = tempfile.mkdtemp(prefix="tracker_verify_", dir="/home/user")
    token = uuid.uuid4().hex
    first_binary = os.path.join(fixture_dir, "program_" + uuid.uuid4().hex)
    second_binary = os.path.join(fixture_dir, "program_" + uuid.uuid4().hex)
    text_file = os.path.join(fixture_dir, "not_elf_" + uuid.uuid4().hex)
    data_file = os.path.join(fixture_dir, "config_" + uuid.uuid4().hex)

    shutil.copy2("/bin/date", first_binary)
    shutil.copy2("/bin/echo", second_binary)
    with open(text_file, "w") as f:
        f.write("#!/bin/sh\necho this is text, not an ELF file\n")
    os.chmod(text_file, 0o755)
    with open(data_file, "w") as f:
        f.write("random configuration data\n")

    first_id = "verify-" + token[:12]
    second_id = "verify-" + token[12:24]
    manifest = {
        "deployments": [
            {"id": first_id, "path": first_binary},
            {"id": "text-" + token[:10], "path": text_file},
            {"id": second_id, "path": second_binary},
            {"id": "data-" + token[10:20], "path": data_file},
        ]
    }

    try:
        with open(MANIFEST_PATH, "w") as f:
            json.dump(manifest, f)

        run_tracker()

        first_interp = get_interpreter(first_binary)
        second_interp = get_interpreter(second_binary)
        assert first_interp is not None
        assert second_interp is not None

        expected_rows = [
            [first_id, first_binary, first_interp],
            [second_id, second_binary, second_interp],
        ]
        actual_rows = read_csv()
        assert len(actual_rows) == 2, (
            f"Expected exactly the two ELF deployments, got: {actual_rows}"
        )
        for expected_row in expected_rows:
            assert expected_row in actual_rows, (
                f"Expected dynamically generated row {expected_row}, got {actual_rows}"
            )
    finally:
        with open(MANIFEST_PATH, "wb") as f:
            f.write(original_manifest)
        shutil.rmtree(fixture_dir, ignore_errors=True)
        run_tracker()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
