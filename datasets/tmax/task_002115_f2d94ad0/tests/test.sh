#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import stat
import subprocess
import tempfile
import uuid

import pytest

TARGET_DIR = "/home/user/settings_chunks"
CONFIG_DIR = "/home/user/system_configs"


def test_settings_chunks_directory_exists():
    """Verify that the settings_chunks directory was created."""
    assert os.path.isdir(TARGET_DIR), f"Directory {TARGET_DIR} is missing. The script did not create it or created it in the wrong place."


def test_settings_chunks_files_exist():
    """Verify that exactly the expected chunk files exist in the directory."""
    assert os.path.isdir(TARGET_DIR), "Target directory missing."

    files = set(os.listdir(TARGET_DIR))
    expected_files = {"chunk_1.json", "chunk_2.json", "chunk_3.json"}
    assert files == expected_files, f"Expected exactly files {expected_files} in {TARGET_DIR}, but found {files}."


def test_settings_chunks_content_and_format():
    """Verify the parsed contents and formatting of each chunk file."""
    expected_data = {
        "chunk_1.json": {"debug": "false", "host": "127.0.0.1"},
        "chunk_2.json": {"mode": "silent", "port": "9090"},
        "chunk_3.json": {"retry": "5", "timeout": "30"},
    }

    for filename, expected_json in expected_data.items():
        filepath = os.path.join(TARGET_DIR, filename)
        assert os.path.isfile(filepath), f"File {filepath} is missing."

        with open(filepath, "r") as f:
            raw_content = f.read()

        try:
            parsed_json = json.loads(raw_content)
        except json.JSONDecodeError:
            pytest.fail(f"File {filename} does not contain valid JSON.")

        assert parsed_json == expected_json, f"Content of {filename} is incorrect. Expected {expected_json}, got {parsed_json}."

        expected_raw = json.dumps(expected_json, indent=2)
        assert raw_content.strip() == expected_raw.strip(), f"File {filename} is not formatted with exactly 2 spaces of indentation as expected."


def _candidate_scripts():
    ini_times = []
    for root, _, files in os.walk(CONFIG_DIR):
        for name in files:
            if name.endswith(".ini"):
                try:
                    ini_times.append(os.stat(os.path.join(root, name)).st_mtime_ns)
                except OSError:
                    pass
    baseline = min(ini_times) if ini_times else 0

    candidates = []
    for search_root in ("/home/user", "/root", "/tmp", "/workspace"):
        if not os.path.isdir(search_root):
            continue
        for root, dirs, files in os.walk(search_root):
            dirs[:] = [d for d in dirs if d not in {".cache", ".local", "__pycache__", ".git", "settings_chunks"}]
            for name in files:
                if not name.endswith(".py"):
                    continue
                path = os.path.join(root, name)
                if path == "/tmp/test_final_state.py" or path.startswith("/tests/"):
                    continue
                try:
                    info = os.lstat(path)
                except OSError:
                    continue
                if stat.S_ISREG(info.st_mode) and info.st_mtime_ns >= baseline:
                    candidates.append(path)
    return sorted(set(candidates))


def _write_ini(path, metadata, settings):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("[Metadata]\n")
        for key, value in metadata.items():
            f.write(f"{key} = {value}\n")
        f.write("\n[Settings]\n")
        for key, value in settings.items():
            f.write(f"{key} = {value}\n")


def _install_probe_fixture(config_backup):
    if os.path.exists(CONFIG_DIR):
        shutil.rmtree(CONFIG_DIR)
    shutil.copytree(config_backup, CONFIG_DIR)

    for root, _, files in os.walk(CONFIG_DIR):
        for name in files:
            if name.endswith(".ini"):
                os.remove(os.path.join(root, name))

    if os.path.exists(TARGET_DIR):
        shutil.rmtree(TARGET_DIR)

    token = uuid.uuid4().hex
    values = {name: f"{name}-{token}" for name in (
        "alpha_old", "alpha_new", "beta", "charlie", "delta_old",
        "delta_new", "epsilon", "foxtrot", "golf", "ignored"
    )}

    _write_ini(
        os.path.join(CONFIG_DIR, "base.ini"),
        {"version": "11", "track_changes": "true"},
        {"alpha": values["alpha_old"], "delta": values["delta_old"], "golf": values["golf"]},
    )
    _write_ini(
        os.path.join(CONFIG_DIR, "deep", "nested", "override.ini"),
        {"version": "47", "track_changes": "true"},
        {"beta": values["beta"], "delta": values["delta_new"], "foxtrot": values["foxtrot"]},
    )
    _write_ini(
        os.path.join(CONFIG_DIR, "other", "additional.ini"),
        {"version": "23", "track_changes": "true"},
        {"alpha": values["alpha_new"], "charlie": values["charlie"], "epsilon": values["epsilon"]},
    )
    _write_ini(
        os.path.join(CONFIG_DIR, "ignored_false.ini"),
        {"version": "61", "track_changes": "false"},
        {"beta": values["ignored"], "hotel": values["ignored"]},
    )
    _write_ini(
        os.path.join(CONFIG_DIR, "ignored_missing.ini"),
        {"version": "70"},
        {"india": values["ignored"]},
    )

    return {
        "alpha": values["alpha_new"],
        "beta": values["beta"],
        "charlie": values["charlie"],
        "delta": values["delta_new"],
        "epsilon": values["epsilon"],
        "foxtrot": values["foxtrot"],
        "golf": values["golf"],
    }


def _probe_output_matches(expected_master):
    sorted_items = sorted(expected_master.items())
    expected_chunks = [dict(sorted_items[i:i + 2]) for i in range(0, len(sorted_items), 2)]
    expected_files = {f"chunk_{i}.json" for i in range(1, len(expected_chunks) + 1)}

    if not os.path.isdir(TARGET_DIR) or set(os.listdir(TARGET_DIR)) != expected_files:
        return False

    for index, expected in enumerate(expected_chunks, 1):
        path = os.path.join(TARGET_DIR, f"chunk_{index}.json")
        try:
            with open(path, "r") as f:
                raw = f.read()
            parsed = json.loads(raw)
        except (OSError, json.JSONDecodeError):
            return False
        if parsed != expected or raw.strip() != json.dumps(expected, indent=2).strip():
            return False
    return True


def test_created_python_script_executes_full_workflow():
    candidates = _candidate_scripts()
    assert candidates, "No created Python script was found."

    backup_root = tempfile.mkdtemp(prefix="config-verifier-backup-")
    config_backup = os.path.join(backup_root, "system_configs")
    output_backup = os.path.join(backup_root, "settings_chunks")
    shutil.copytree(CONFIG_DIR, config_backup)
    had_output = os.path.exists(TARGET_DIR)
    if had_output:
        shutil.copytree(TARGET_DIR, output_backup)

    errors = []
    passed = False
    try:
        for script in candidates:
            expected = _install_probe_fixture(config_backup)
            try:
                result = subprocess.run(
                    ["python3", script],
                    cwd=os.path.dirname(script) or "/",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=15,
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                errors.append(f"{script}: {exc}")
                continue

            if result.returncode == 0 and _probe_output_matches(expected):
                passed = True
                break
            errors.append(f"{script}: exit={result.returncode}, stderr={result.stderr[-300:]}")
    finally:
        if os.path.exists(CONFIG_DIR):
            shutil.rmtree(CONFIG_DIR)
        shutil.copytree(config_backup, CONFIG_DIR)
        if os.path.exists(TARGET_DIR):
            shutil.rmtree(TARGET_DIR)
        if had_output:
            shutil.copytree(output_backup, TARGET_DIR)
        shutil.rmtree(backup_root)

    assert passed, "No created Python script correctly parsed and merged a randomized recursive INI fixture. " + " | ".join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
