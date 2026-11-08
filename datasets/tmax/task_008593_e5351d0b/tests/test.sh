#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import subprocess
import pytest

RAW_DIR = "/home/user/research_data/raw"
BACKUP_DIR = "/home/user/research_data/incremental_backup"
LOG_FILE = "/home/user/processed_log.json"
LAST_RUN_FILE = "/home/user/last_run.txt"


def test_processed_log():
    log_file = "/home/user/processed_log.json"
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist."

    with open(log_file, "r") as f:
        try:
            log_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {log_file} is not valid JSON.")

    expected_data = {
        "data1.csv": 110,
        "data3.xml": 350,
        "data5.json": 105
    }

    assert log_data == expected_data, f"Log file contents {log_data} do not match expected {expected_data}."


def test_incremental_backup():
    backup_dir = "/home/user/research_data/incremental_backup/"
    assert os.path.isdir(backup_dir), f"Backup directory {backup_dir} does not exist."

    backed_up_files = set(os.listdir(backup_dir))
    expected_files = {"data3.xml", "data5.json"}

    assert backed_up_files == expected_files, f"Backup directory contains {backed_up_files}, expected {expected_files}."

    # Verify contents match the original
    raw_dir = "/home/user/research_data/raw/"
    for filename in expected_files:
        raw_path = os.path.join(raw_dir, filename)
        backup_path = os.path.join(backup_dir, filename)

        with open(raw_path, "r") as f:
            raw_content = f.read()

        with open(backup_path, "r") as f:
            backup_content = f.read()

        assert raw_content == backup_content, f"Content of backed up file {filename} does not match the original."


def discover_python_scripts():
    roots = ["/home", "/root", "/workspace", "/app", "/tmp"]
    excluded_files = {"/tmp/test_final_state.py"}
    excluded_dirs = {
        "/tests", "/logs", "/proc", "/sys", "/dev",
        "/root/.cache", "/root/.local", "/tmp/pytest-of-root"
    }
    scripts = []

    for root in roots:
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [
                d for d in dirs
                if os.path.join(current, d) not in excluded_dirs
                and d not in {"__pycache__", ".git", "site-packages", "dist-packages"}
            ]
            for filename in files:
                path = os.path.abspath(os.path.join(current, filename))
                if filename.endswith(".py") and path not in excluded_files and os.path.isfile(path):
                    scripts.append(path)

    for filename in os.listdir("/"):
        path = os.path.join("/", filename)
        if filename.endswith(".py") and os.path.isfile(path):
            scripts.append(path)

    return sorted(set(scripts))


def clear_directory(path):
    os.makedirs(path, exist_ok=True)
    for name in os.listdir(path):
        item = os.path.join(path, name)
        if os.path.isdir(item) and not os.path.islink(item):
            shutil.rmtree(item)
        else:
            os.unlink(item)


def install_dynamic_fixture(spec):
    os.makedirs(RAW_DIR, exist_ok=True)
    # Preserve possible script files, but remove all supported input files.
    for name in os.listdir(RAW_DIR):
        path = os.path.join(RAW_DIR, name)
        if os.path.isfile(path) and name.lower().endswith((".csv", ".json", ".xml")):
            os.unlink(path)

    clear_directory(BACKUP_DIR)
    if os.path.lexists(LOG_FILE):
        os.unlink(LOG_FILE)

    with open(LAST_RUN_FILE, "w") as f:
        f.write(str(spec["last_run"]))

    for filename, content, mtime in spec["files"]:
        path = os.path.join(RAW_DIR, filename)
        with open(path, "w") as f:
            f.write(content)
        os.utime(path, (mtime, mtime))

    ignored = os.path.join(RAW_DIR, spec["ignored_name"])
    with open(ignored, "w") as f:
        f.write("reading\n999999\n")
    os.utime(ignored, (spec["last_run"] + 10, spec["last_run"] + 10))


def dynamic_result_matches(spec):
    if not os.path.isfile(LOG_FILE) or not os.path.isdir(BACKUP_DIR):
        return False
    try:
        with open(LOG_FILE, "r") as f:
            actual_log = json.load(f)
    except (OSError, json.JSONDecodeError):
        return False

    if actual_log != spec["expected_log"]:
        return False
    if set(os.listdir(BACKUP_DIR)) != set(spec["expected_backup"]):
        return False

    for filename in spec["expected_backup"]:
        raw_path = os.path.join(RAW_DIR, filename)
        backup_path = os.path.join(BACKUP_DIR, filename)
        if not os.path.isfile(backup_path):
            return False
        with open(raw_path, "rb") as raw, open(backup_path, "rb") as backup:
            if raw.read() != backup.read():
                return False
    return True


def test_script_exists_and_handles_dynamic_inputs():
    scripts = discover_python_scripts()
    assert scripts, "No Python script was created."

    nonce = secrets.token_hex(8)
    last_run = 1700000000 + secrets.randbelow(1000000)
    csv_old_values = [70 + secrets.randbelow(20), 60 + secrets.randbelow(20)]
    json_new_values = [80 + secrets.randbelow(20), 50 + secrets.randbelow(20)]
    xml_equal_values = [101 + secrets.randbelow(20)]
    xml_new_values = [55 + secrets.randbelow(10), 56 + secrets.randbelow(10)]

    csv_old = f"old_{nonce}.csv"
    csv_exact = f"exact_{nonce}.csv"
    json_new = f"new_{nonce}.json"
    json_small = f"small_{nonce}.json"
    xml_equal = f"equal_{nonce}.xml"
    xml_new = f"fresh_{nonce}.xml"

    files = [
        (csv_old, "seq,reading,label\n1,%d,a\n2,%d,b\n" % tuple(csv_old_values), last_run - 5),
        (csv_exact, "seq,reading\n1,40\n2,60\n", last_run + 5),
        (json_new, json.dumps({"readings": json_new_values}), last_run + 1),
        (json_small, json.dumps({"readings": [20, 30, 40]}), last_run + 2),
        (xml_equal, "<data>" + "".join(f"<reading>{v}</reading>" for v in xml_equal_values) + "</data>", last_run),
        (xml_new, "<data>" + "".join(f"<reading>{v}</reading>" for v in xml_new_values) + "</data>", last_run + 9),
    ]
    spec = {
        "last_run": last_run,
        "files": files,
        "ignored_name": f"ignored_{nonce}.txt",
        "expected_log": {
            csv_old: sum(csv_old_values),
            json_new: sum(json_new_values),
            xml_equal: sum(xml_equal_values),
            xml_new: sum(xml_new_values),
        },
        "expected_backup": {json_new, xml_new},
    }

    failures = []
    for script in scripts:
        install_dynamic_fixture(spec)
        try:
            result = subprocess.run(
                ["python3", script],
                cwd=os.path.dirname(script) or "/",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
        except Exception as exc:
            failures.append(f"{script}: {exc}")
            continue

        if result.returncode == 0 and dynamic_result_matches(spec):
            return
        failures.append(
            f"{script}: exit={result.returncode}, stderr={result.stderr[-300:]}"
        )

    pytest.fail("No submitted Python script produced the required result on dynamic inputs. " + " | ".join(failures[-10:]))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
