#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import stat
import subprocess

SCRIPT = "/home/user/config_manager.py"
INCOMING = "/home/user/incoming_configs"
PROCESSED = "/home/user/processed_configs"
LOG = "/home/user/sync_log.txt"


def test_config_manager_script_exists():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} is missing."
    assert not os.path.islink(SCRIPT), f"Script {SCRIPT} must be a regular file, not a symlink."
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"Script {SCRIPT} is not a regular file."


def test_incoming_directory_empty():
    incoming_dir = "/home/user/incoming_configs"
    assert os.path.isdir(incoming_dir), f"Directory {incoming_dir} is missing."
    files = os.listdir(incoming_dir)
    assert len(files) == 0, f"Directory {incoming_dir} is not empty. Found: {files}"


def test_processed_configs_files():
    processed_dir = "/home/user/processed_configs"
    assert os.path.isdir(processed_dir), f"Directory {processed_dir} is missing."

    expected_files = {
        "nginx_v1.21.0.json",
        "postgres_v14.2.xml",
        "redis_v6.2.6.csv"
    }

    actual_files = set(os.listdir(processed_dir))
    assert actual_files == expected_files, f"Expected files {expected_files} in {processed_dir}, but found {actual_files}."


def test_processed_configs_retain_original_contents():
    expected_contents = {
        "nginx_v1.21.0.json": b'{\n  "app_name": "nginx",\n  "version": "1.21.0",\n  "port": 80\n}\n',
        "postgres_v14.2.xml": b'<root>\n  <app_name>postgres</app_name>\n  <version>14.2</version>\n  <max_connections>100</max_connections>\n</root>\n',
        "redis_v6.2.6.csv": b'app_name,version,memory\nredis,6.2.6,2GB\n',
    }
    for filename, expected in expected_contents.items():
        path = os.path.join(PROCESSED, filename)
        with open(path, "rb") as f:
            actual = f.read()
        assert actual == expected, f"Processed file {filename} did not retain its original contents."


def test_sync_log_content():
    log_file = "/home/user/sync_log.txt"
    assert os.path.isfile(log_file), f"Log file {log_file} is missing."

    expected_lines = [
        "[WATCHER] cache.csv moved to redis_v6.2.6.csv\n",
        "[WATCHER] db.xml moved to postgres_v14.2.xml\n",
        "[WATCHER] web.json moved to nginx_v1.21.0.json\n"
    ]

    with open(log_file, "r") as f:
        actual_lines = f.readlines()

    assert actual_lines == expected_lines, "The contents of sync_log.txt do not match the expected sorted format."


def test_script_processes_fresh_dynamic_inputs():
    token = secrets.token_hex(8)
    cases = [
        {
            "original": f"z_{token}.json",
            "app": f"jsonapp_{token}",
            "version": f"9.{secrets.randbelow(9000) + 1000}",
            "extension": "json",
        },
        {
            "original": f"a_{token}.xml",
            "app": f"xmlapp_{token}",
            "version": f"8.{secrets.randbelow(9000) + 1000}",
            "extension": "xml",
        },
        {
            "original": f"m_{token}.csv",
            "app": f"csvapp_{token}",
            "version": f"7.{secrets.randbelow(9000) + 1000}",
            "extension": "csv",
        },
    ]

    shutil.rmtree(INCOMING, ignore_errors=True)
    shutil.rmtree(PROCESSED, ignore_errors=True)
    os.makedirs(INCOMING)
    os.makedirs(PROCESSED)
    if os.path.lexists(LOG):
        os.remove(LOG)

    original_bytes = {}
    for case in cases:
        path = os.path.join(INCOMING, case["original"])
        if case["extension"] == "json":
            data = (json.dumps({
                "app_name": case["app"],
                "version": case["version"],
                "preserve": f"payload-{token}",
            }, indent=2) + "\n").encode()
        elif case["extension"] == "xml":
            data = (
                f"<configuration>\n"
                f"  <app_name>{case['app']}</app_name>\n"
                f"  <version>{case['version']}</version>\n"
                f"  <preserve>payload-{token}</preserve>\n"
                f"</configuration>\n"
            ).encode()
        else:
            data = (
                f"preserve,version,app_name\n"
                f"payload-{token},{case['version']},{case['app']}\n"
                f"second-row,0.0,ignored-{token}\n"
            ).encode()
        with open(path, "wb") as f:
            f.write(data)
        original_bytes[case["original"]] = data

    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"config_manager.py failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"

    assert os.path.isdir(INCOMING), f"Directory {INCOMING} is missing after execution."
    assert os.listdir(INCOMING) == [], f"Fresh input files were not all moved: {os.listdir(INCOMING)}"

    expected_names = {
        f"{case['app']}_v{case['version']}.{case['extension']}"
        for case in cases
    }
    actual_names = set(os.listdir(PROCESSED))
    assert actual_names == expected_names, f"Expected dynamic outputs {expected_names}, found {actual_names}."

    for case in cases:
        destination = f"{case['app']}_v{case['version']}.{case['extension']}"
        destination_path = os.path.join(PROCESSED, destination)
        assert os.path.isfile(destination_path), f"Processed output {destination} is not a file."
        with open(destination_path, "rb") as f:
            assert f.read() == original_bytes[case["original"]], f"Contents changed while moving {case['original']}."

    expected_log = [
        f"[WATCHER] {case['original']} moved to {case['app']}_v{case['version']}.{case['extension']}\n"
        for case in sorted(cases, key=lambda item: item["original"])
    ]
    assert os.path.isfile(LOG), f"Log file {LOG} is missing after dynamic execution."
    with open(LOG, "r") as f:
        actual_log = f.readlines()
    assert actual_log == expected_log, f"Dynamic log was incorrect or unsorted. Expected {expected_log}, found {actual_log}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
