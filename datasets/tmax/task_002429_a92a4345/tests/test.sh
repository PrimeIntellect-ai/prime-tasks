#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import stat
import subprocess
import uuid


def test_backup_directory_contents():
    """Verify that the backup directory contains the original files before transformation."""
    backup_base = "/home/user/backup_drive/projects_backup"

    expected_files = {
        os.path.join(backup_base, "proj_alpha", "users.csv"): "id,username,role\n1,admin,superuser\n2,bob,editor",
        os.path.join(backup_base, "proj_beta", "settings.json"): '{"theme": "dark"}',
        os.path.join(backup_base, "proj_beta", "sub_dir", "metrics.csv"): "date,clicks,views\n2023-01-01,50,1000\n2023-01-02,75,1200"
    }

    for filepath, expected_content in expected_files.items():
        assert os.path.isfile(filepath), f"Backup file missing: {filepath}"
        with open(filepath, "r") as f:
            content = f.read().strip()
            assert content == expected_content.strip(), f"Content mismatch in backup file {filepath}"


def test_no_csv_files_in_old_projects():
    """Verify that no .csv files remain in the old_projects directory."""
    old_projects_base = "/home/user/old_projects"

    csv_files = []
    for root, dirs, files in os.walk(old_projects_base):
        for file in files:
            if file.endswith(".csv"):
                csv_files.append(os.path.join(root, file))

    assert len(csv_files) == 0, f"Found remaining .csv files in {old_projects_base}: {csv_files}"


def test_json_conversion_contents():
    """Verify that the .csv files were correctly converted to .json."""
    users_json_path = "/home/user/old_projects/proj_alpha/users.json"
    metrics_json_path = "/home/user/old_projects/proj_beta/sub_dir/metrics.json"

    assert os.path.isfile(users_json_path), f"Converted JSON file missing: {users_json_path}"
    assert os.path.isfile(metrics_json_path), f"Converted JSON file missing: {metrics_json_path}"

    with open(users_json_path, "r") as f:
        users_data = json.load(f)

    expected_users_data = [
        {"id": "1", "username": "admin", "role": "superuser"},
        {"id": "2", "username": "bob", "role": "editor"}
    ]
    assert users_data == expected_users_data, f"JSON content mismatch in {users_json_path}"

    with open(metrics_json_path, "r") as f:
        metrics_data = json.load(f)

    expected_metrics_data = [
        {"date": "2023-01-01", "clicks": "50", "views": "1000"},
        {"date": "2023-01-02", "clicks": "75", "views": "1200"}
    ]
    assert metrics_data == expected_metrics_data, f"JSON content mismatch in {metrics_json_path}"


def test_existing_json_untouched():
    """Verify that the existing JSON file was not modified, including its bytes."""
    settings_json_path = "/home/user/old_projects/proj_beta/settings.json"
    assert os.path.isfile(settings_json_path), f"Existing JSON file missing: {settings_json_path}"

    with open(settings_json_path, "r") as f:
        settings_data = json.load(f)

    assert settings_data == {"theme": "dark"}, f"Existing JSON file was modified: {settings_json_path}"
    with open(settings_json_path, "rb") as f:
        assert f.read() == b'{"theme": "dark"}\n', "Existing JSON file was not preserved byte-for-byte"


def test_conversion_log():
    """Verify the contents of the conversion log."""
    log_path = "/home/user/conversion_log.txt"
    assert os.path.isfile(log_path), f"Conversion log missing: {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "/home/user/old_projects/proj_alpha/users.json",
        "/home/user/old_projects/proj_beta/sub_dir/metrics.json"
    ]

    assert lines == expected_lines, f"Log contents mismatch or not sorted correctly. Expected {expected_lines}, got {lines}"


def test_script_exists_and_performs_general_recursive_conversion():
    """Execute the submitted script against fresh, unpredictable nested CSV files."""
    script_path = "/home/user/transform_projects.py"
    assert os.path.exists(script_path), f"Required script missing: {script_path}"
    mode = os.lstat(script_path).st_mode
    assert stat.S_ISREG(mode), f"Required script is not a regular file: {script_path}"

    old_projects = "/home/user/old_projects"
    token = uuid.uuid4().hex
    case_root = os.path.join(old_projects, token)
    csv_paths = [
        os.path.join(case_root, "deep", "z_" + token[:8] + ".csv"),
        os.path.join(case_root, "other", "a_" + token[8:16] + ".csv"),
    ]

    for path in csv_paths:
        os.makedirs(os.path.dirname(path), exist_ok=True)

    with open(csv_paths[0], "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["key_" + token[:6], "description", "amount"])
        writer.writerow([token[16:24], "value, with comma", "007"])
        writer.writerow([token[24:32], "", "19"])

    with open(csv_paths[1], "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["name", "code_" + token[-6:]])
        writer.writerow(["alpha", token[:12]])
        writer.writerow(["beta", token[-12:]])

    expected = {}
    for path in csv_paths:
        with open(path, "r", newline="", encoding="utf-8") as f:
            expected[os.path.splitext(path)[0] + ".json"] = list(csv.DictReader(f))

    sentinel_path = os.path.join(case_root, "deep", "preexisting.json")
    sentinel_bytes = ('{  "sentinel": "' + token + '"  }\n').encode("utf-8")
    with open(sentinel_path, "wb") as f:
        f.write(sentinel_bytes)

    existing_json = {}
    for root, dirs, files in os.walk(old_projects):
        for name in files:
            if name.endswith(".json") and os.path.join(root, name) not in expected:
                path = os.path.join(root, name)
                with open(path, "rb") as f:
                    existing_json[path] = f.read()

    result = subprocess.run(
        ["python3", script_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Submitted script failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    for csv_path in csv_paths:
        assert not os.path.exists(csv_path), f"Script did not delete converted CSV: {csv_path}"

    for json_path, expected_rows in expected.items():
        assert os.path.isfile(json_path), f"Script did not create JSON: {json_path}"
        with open(json_path, "r", encoding="utf-8") as f:
            assert json.load(f) == expected_rows, f"Incorrect conversion result in {json_path}"

    for path, original_bytes in existing_json.items():
        assert os.path.isfile(path), f"Existing JSON was removed: {path}"
        with open(path, "rb") as f:
            assert f.read() == original_bytes, f"Existing JSON was modified byte-for-byte: {path}"

    log_path = "/home/user/conversion_log.txt"
    assert os.path.isfile(log_path), f"Conversion log missing after script execution: {log_path}"
    with open(log_path, "r", encoding="utf-8") as f:
        logged_paths = [line.strip() for line in f if line.strip()]
    assert logged_paths == sorted(expected), (
        f"Dynamic conversion log was not exactly the sorted list of newly created JSON files: {logged_paths}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
