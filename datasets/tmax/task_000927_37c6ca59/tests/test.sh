#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import uuid
import pytest


def test_file_permissions():
    """Verify that the permissions of the files are correct after remediation."""
    files_and_perms = {
        "/home/user/project/processor.py": 0o775,
        "/home/user/project/helper.py": 0o755,
        "/home/user/project/network.py": 0o666,
        "/home/user/project/utils.py": 0o775,
    }

    for filepath, expected_perm in files_and_perms.items():
        assert os.path.isfile(filepath), f"File {filepath} does not exist."
        actual_perm = os.stat(filepath).st_mode & 0o777
        assert actual_perm == expected_perm, (
            f"File {filepath} has incorrect permissions. "
            f"Expected {oct(expected_perm)}, got {oct(actual_perm)}."
        )


def test_remediated_files_json():
    """Verify that the JSON output file contains exactly the remediated files."""
    json_path = "/home/user/remediated_files.json"
    assert os.path.isfile(json_path), f"Output file {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} does not contain valid JSON.")

    assert isinstance(data, list), f"Data in {json_path} should be a JSON array."

    expected_files = {
        "/home/user/project/processor.py",
        "/home/user/project/utils.py",
    }
    actual_files = set(data)
    assert actual_files == expected_files, (
        f"Incorrect files listed in {json_path}. "
        f"Expected {expected_files}, got {actual_files}."
    )
    assert len(data) == len(expected_files), (
        f"The array in {json_path} contains duplicate or extra entries."
    )


def test_remediation_script_on_derived_inputs():
    script_path = "/home/user/remediate.py"
    assert os.path.exists(script_path), f"Required script {script_path} does not exist."
    assert stat.S_ISREG(os.lstat(script_path).st_mode), (
        f"Required script {script_path} must be a regular file."
    )

    token = uuid.uuid4().hex
    project = "/home/user/project"
    flagged_one = os.path.join(project, f"flagged_{token}_one.py")
    flagged_two = os.path.join(project, f"flagged_{token}_two.py")
    already_safe = os.path.join(project, f"safe_{token}.py")
    wrong_alert = os.path.join(project, f"network_{token}.py")
    unmentioned = os.path.join(project, f"unmentioned_{token}.py")
    created = [flagged_one, flagged_two, already_safe, wrong_alert, unmentioned]

    log_path = "/home/user/ids_alerts.log"
    output_path = "/home/user/remediated_files.json"
    with open(log_path, "rb") as f:
        original_log = f.read()
    output_existed = os.path.exists(output_path)
    original_output = None
    if output_existed:
        with open(output_path, "rb") as f:
            original_output = f.read()

    try:
        for path in created:
            with open(path, "w") as f:
                f.write("# verifier-generated test file\n")

        initial_modes = {
            flagged_one: 0o707,
            flagged_two: 0o676,
            already_safe: 0o751,
            wrong_alert: 0o606,
            unmentioned: 0o777,
        }
        for path, mode in initial_modes.items():
            os.chmod(path, mode)

        with open(log_path, "w") as f:
            f.write(
                f"[2026-01-02 03:04:05] [ALERT-SBX-09] Suspicious activity in {flagged_one}\n"
                f"[2026-01-02 03:05:05] [ALERT-NET-01] Outbound connection blocked from {wrong_alert}\n"
                f"[2026-01-02 03:06:05] [ALERT-SBX-09] Suspicious activity in {already_safe}\n"
                f"[2026-01-02 03:07:05] [ALERT-SBX-09] Suspicious activity in {flagged_two}\n"
                f"[2026-01-02 03:08:05] [ALERT-SBX-09] Suspicious activity in {flagged_one}\n"
            )

        result = subprocess.run(
            ["python3", script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"{script_path} failed when executed. stdout={result.stdout!r}, "
            f"stderr={result.stderr!r}"
        )
        assert stat.S_ISREG(os.lstat(script_path).st_mode), (
            f"Required script {script_path} was not preserved as a regular file."
        )

        expected_modes = {
            flagged_one: 0o705,
            flagged_two: 0o674,
            already_safe: 0o751,
            wrong_alert: 0o606,
            unmentioned: 0o777,
        }
        for path, expected_mode in expected_modes.items():
            actual_mode = os.stat(path).st_mode & 0o777
            assert actual_mode == expected_mode, (
                f"{path} has mode {oct(actual_mode)}; expected {oct(expected_mode)}."
            )

        assert os.path.isfile(output_path), f"Output file {output_path} was not created."
        try:
            with open(output_path, "r") as f:
                data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} does not contain valid JSON after execution.")

        assert isinstance(data, list), f"Data in {output_path} should be a JSON array."
        expected_modified = {flagged_one, flagged_two}
        assert set(data) == expected_modified, (
            f"Expected dynamically flagged modified files {expected_modified}, got {set(data)}."
        )
        assert len(data) == len(expected_modified), (
            f"The array in {output_path} contains duplicate or extra entries."
        )
    finally:
        with open(log_path, "wb") as f:
            f.write(original_log)
        if output_existed:
            with open(output_path, "wb") as f:
                f.write(original_output)
        elif os.path.exists(output_path):
            os.remove(output_path)
        for path in created:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
