#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import shutil
import subprocess
import tempfile
import uuid

import pytest
import yaml


def test_backup_archive_exists():
    assert os.path.isdir("/home/user/backup_archive"), "Directory /home/user/backup_archive was not created."


def test_backed_up_files():
    active_config_path = "/home/user/backup_archive/active_config.json"
    settings_path = "/home/user/backup_archive/settings.json"

    assert os.path.isfile(active_config_path), "active_config.json was not backed up."
    assert os.path.isfile(settings_path), "settings.json was not backed up."

    with open(active_config_path, "rb") as backed_up, open("/home/user/app_configs/sub2/active_config.json", "rb") as original:
        assert backed_up.read() == original.read(), "active_config.json content does not match the source file."
    with open(settings_path, "rb") as backed_up, open("/home/user/app_configs/settings.json", "rb") as original:
        assert backed_up.read() == original.read(), "settings.json content does not match the source file."


def test_not_backed_up_files():
    assert not os.path.isfile("/home/user/backup_archive/old_config.json"), "old_config.json should not be backed up (mtime is older than last backup)."
    assert not os.path.isfile("/home/user/backup_archive/legacy.json"), "legacy.json should not be backed up (mtime is older than last backup)."
    assert not os.path.isfile("/home/user/backup_archive/data.xml"), "data.xml should not be backed up (wrong extension)."


def test_backup_report_yaml():
    yaml_path = "/home/user/backup_report.yaml"
    assert os.path.isfile(yaml_path), "backup_report.yaml was not created."

    with open(yaml_path, 'r') as f:
        content = f.read()

    assert "backed_up_files:" in content, "The key 'backed_up_files:' is missing in the YAML report."

    # Preserve the original report checks.
    filenames = re.findall(r'filename:\s*["\']?(.*?)["\']?(?:\n|$)', content)
    sizes = re.findall(r'size:\s*(\d+)', content)

    assert len(filenames) == 2, f"Expected 2 filenames in the report, found {len(filenames)}."
    assert len(sizes) == 2, f"Expected 2 sizes in the report, found {len(sizes)}."
    assert filenames == sorted(filenames), "Filenames in the report are not sorted alphabetically."
    assert filenames[0] == "active_config.json", f"Expected active_config.json as the first file, got {filenames[0]}"
    assert filenames[1] == "settings.json", f"Expected settings.json as the second file, got {filenames[1]}"

    active_size = os.path.getsize("/home/user/app_configs/sub2/active_config.json")
    settings_size = os.path.getsize("/home/user/app_configs/settings.json")
    assert int(sizes[0]) == active_size, f"Incorrect size for active_config.json: expected {active_size}, got {sizes[0]}"
    assert int(sizes[1]) == settings_size, f"Incorrect size for settings.json: expected {settings_size}, got {sizes[1]}"


def _python_script_candidates():
    excluded = {
        "/home/user/last_backup.json",
        "/home/user/backup_report.yaml",
    }
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        if root.startswith("/home/user/app_configs") or root.startswith("/home/user/backup_archive"):
            continue
        for name in files:
            path = os.path.join(root, name)
            if path in excluded or name.endswith((".json", ".yaml", ".yml", ".xml", ".pyc")):
                continue
            try:
                with open(path, "r", encoding="utf-8") as f:
                    source = f.read()
                tree = ast.parse(source, filename=path)
                if tree.body:
                    candidates.append(path)
            except (OSError, UnicodeError, SyntaxError):
                continue
    return sorted(set(candidates))


def test_written_script_handles_derived_incremental_inputs():
    candidates = _python_script_candidates()
    assert candidates, "No Python backup script was found under /home/user."

    archive = "/home/user/backup_archive"
    report = "/home/user/backup_report.yaml"
    last_backup = "/home/user/last_backup.json"
    app_configs = "/home/user/app_configs"

    token = uuid.uuid4().hex
    newer_names = sorted([f"a_{token}.json", f"z_{token}.json"])
    equal_name = f"equal_{token}.json"
    older_name = f"older_{token}.json"
    non_json_name = f"ignored_{token}.txt"
    probe_dir = os.path.join(app_configs, f"probe_{token}", "nested")
    probe_paths = [os.path.join(probe_dir, n) for n in newer_names + [equal_name, older_name, non_json_name]]
    cutoff = 1800000100

    with tempfile.TemporaryDirectory() as saved:
        saved_archive = os.path.join(saved, "archive")
        saved_report = os.path.join(saved, "report.yaml")
        saved_last = os.path.join(saved, "last_backup.json")
        shutil.copytree(archive, saved_archive)
        shutil.copy2(report, saved_report)
        shutil.copy2(last_backup, saved_last)

        errors = []
        try:
            for candidate in candidates:
                shutil.rmtree(archive, ignore_errors=True)
                if os.path.exists(report):
                    os.remove(report)
                os.makedirs(probe_dir, exist_ok=True)

                payloads = {
                    newer_names[0]: ("first-" + token).encode(),
                    newer_names[1]: ("second-" + token + "-longer").encode(),
                    equal_name: ("equal-" + token).encode(),
                    older_name: ("older-" + token).encode(),
                    non_json_name: ("non-json-" + token).encode(),
                }
                for name, data in payloads.items():
                    path = os.path.join(probe_dir, name)
                    with open(path, "wb") as f:
                        f.write(data)
                for name in newer_names:
                    os.utime(os.path.join(probe_dir, name), (cutoff + 100, cutoff + 100))
                os.utime(os.path.join(probe_dir, equal_name), (cutoff, cutoff))
                os.utime(os.path.join(probe_dir, older_name), (cutoff - 100, cutoff - 100))
                os.utime(os.path.join(probe_dir, non_json_name), (cutoff + 100, cutoff + 100))
                with open(last_backup, "w", encoding="utf-8") as f:
                    json.dump({"last_backup_time": cutoff}, f)

                try:
                    result = subprocess.run(
                        ["python3", candidate],
                        cwd=os.path.dirname(candidate) or "/home/user",
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=20,
                    )
                    assert result.returncode == 0, result.stderr
                    assert os.path.isdir(archive), "backup archive was not created"

                    actual_files = sorted(
                        name for name in os.listdir(archive)
                        if os.path.isfile(os.path.join(archive, name))
                    )
                    assert actual_files == newer_names, f"archive contained {actual_files}, expected {newer_names}"
                    for name in newer_names:
                        with open(os.path.join(archive, name), "rb") as copied:
                            assert copied.read() == payloads[name], f"copied content was wrong for {name}"

                    assert os.path.isfile(report), "backup report was not created"
                    with open(report, "r", encoding="utf-8") as f:
                        parsed = yaml.safe_load(f)
                    expected_entries = [
                        {"filename": name, "size": len(payloads[name])}
                        for name in newer_names
                    ]
                    assert isinstance(parsed, dict), "report is not a YAML mapping"
                    assert parsed.get("backed_up_files") == expected_entries, (
                        f"report entries were {parsed.get('backed_up_files')!r}, expected {expected_entries!r}"
                    )
                    return
                except Exception as exc:
                    errors.append(f"{candidate}: {exc}")

            pytest.fail("No submitted Python script performed the incremental backup correctly:\n" + "\n".join(errors))
        finally:
            shutil.rmtree(probe_dir.split(f"{os.sep}nested")[0], ignore_errors=True)
            shutil.rmtree(archive, ignore_errors=True)
            shutil.copytree(saved_archive, archive)
            shutil.copy2(saved_report, report)
            shutil.copy2(saved_last, last_backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
