#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import shutil
import subprocess
import tempfile
import uuid

import pytest


def test_script_exists():
    script_path = "/home/user/verify_restores.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."


def test_summary_json_exists_and_correct():
    summary_path = "/home/user/summary.json"
    assert os.path.isfile(summary_path), f"Summary file {summary_path} does not exist."

    with open(summary_path, "r") as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {summary_path} is not valid JSON.")

    expected_summary = {
        "/": 3,
        "/var/www": 3,
        "/opt/app/backup": 3,
    }
    assert summary == expected_summary, (
        f"Summary JSON content is incorrect. Expected {expected_summary}, got {summary}."
    )


def test_log_files_exist():
    logs_dir = "/home/user/logs"
    required = [
        "_.log", "_.log.1", "_.log.2",
        "_var_www.log", "_var_www.log.1", "_var_www.log.2",
        "_opt_app_backup.log", "_opt_app_backup.log.1", "_opt_app_backup.log.2",
    ]
    for name in required:
        assert os.path.isfile(os.path.join(logs_dir, name)), f"Log file {name} missing."


def test_log_file_contents():
    root_log = "/home/user/logs/_.log"
    if os.path.isfile(root_log):
        with open(root_log, "r") as f:
            content = f.read()
        assert "VERIFIED: /" in content, (
            f"Log file {root_log} does not contain expected message format."
        )
        assert "INFO" not in content, f"Log file {root_log} should not contain log levels."


def test_script_executes_and_implements_dynamic_fstab_and_logging():
    script = "/home/user/verify_restores.py"
    fstab = "/home/user/backup_data/fstab.mock"
    logs_dir = "/home/user/logs"
    summary_path = "/home/user/summary.json"
    token = uuid.uuid4().hex[:12]
    mounts = [
        f"/verify_{token}/alpha",
        f"/verify_{token}/beta/deep",
        f"/verify_{token}/gamma",
    ]
    ignored = f"/verify_{token}/not_ext4"
    commented = f"/verify_{token}/commented"

    runner = r'''
import json
import logging
import logging.handlers
import os
import runpy
import sys

output_path = sys.argv[2]
original_handler = logging.handlers.RotatingFileHandler
original_info = logging.Logger.info
handlers = []
info_calls = []

class TrackingRotatingFileHandler(original_handler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        handlers.append(self)

def tracking_info(self, msg, *args, **kwargs):
    try:
        rendered = str(msg) % args if args else str(msg)
    except Exception:
        rendered = str(msg)
    info_calls.append(rendered)
    return original_info(self, msg, *args, **kwargs)

logging.handlers.RotatingFileHandler = TrackingRotatingFileHandler
logging.Logger.info = tracking_info
runpy.run_path(sys.argv[1], run_name="__main__")

result = {"info_calls": info_calls, "handlers": []}
for handler in handlers:
    record = logging.LogRecord("audit", logging.INFO, "", 0, "FORMAT_SENTINEL", (), None)
    formatted = handler.format(record)
    result["handlers"].append({
        "baseFilename": os.path.abspath(handler.baseFilename),
        "maxBytes": handler.maxBytes,
        "backupCount": handler.backupCount,
        "formatted": formatted,
    })
with open(output_path, "w") as f:
    json.dump(result, f)
'''

    with tempfile.TemporaryDirectory() as temp_dir:
        logs_backup = os.path.join(temp_dir, "logs_backup")
        shutil.copytree(logs_dir, logs_backup)
        with open(fstab, "rb") as f:
            old_fstab = f.read()
        old_summary_exists = os.path.exists(summary_path)
        old_summary = None
        if old_summary_exists:
            with open(summary_path, "rb") as f:
                old_summary = f.read()

        instrumentation = os.path.join(temp_dir, "instrumentation.json")
        try:
            for entry in os.listdir(logs_dir):
                path = os.path.join(logs_dir, entry)
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.unlink(path)
            if os.path.exists(summary_path):
                os.unlink(summary_path)

            dynamic_fstab = f"""# randomized verifier input

/dev/a {mounts[0]} ext4 defaults 0 0
/dev/b {ignored} xfs defaults 0 0
   # /dev/c {commented} ext4 defaults 0 0
/dev/d {mounts[1]} ext4 rw,nosuid 0 2
/dev/e /verify_{token}/ext4ish ext4plus defaults 0 0
/dev/f {mounts[2]} ext4 ro 1 2
"""
            with open(fstab, "w") as f:
                f.write(dynamic_fstab)

            completed = subprocess.run(
                ["python3", "-c", runner, script, instrumentation],
                cwd="/home/user",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
            assert completed.returncode == 0, (
                "verify_restores.py did not execute successfully on a new fstab input.\n"
                f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
            )
            assert os.path.isfile(instrumentation), "Logging instrumentation was not produced."
            with open(instrumentation, "r") as f:
                observed = json.load(f)

            expected_summary = {mount: 3 for mount in mounts}
            assert os.path.isfile(summary_path), "The executed script did not create summary.json."
            with open(summary_path, "r") as f:
                actual_summary = json.load(f)
            assert actual_summary == expected_summary, (
                f"The script did not derive its summary from the supplied fstab: {actual_summary}"
            )

            expected_files = set()
            for mount in mounts:
                stem = mount.replace("/", "_") + ".log"
                names = {stem, stem + ".1", stem + ".2"}
                expected_files.update(names)
                for name in names:
                    path = os.path.join(logs_dir, name)
                    assert os.path.isfile(path), f"Expected rotated log file {name} was not generated."
                    with open(path, "r") as f:
                        lines = f.read().splitlines()
                    assert lines, f"Generated log file {name} is empty."
                    assert all(line == f"VERIFIED: {mount}" for line in lines), (
                        f"Log file {name} contains incorrectly formatted messages: {lines}"
                    )
            assert set(os.listdir(logs_dir)) == expected_files, (
                "Logs were generated for non-ext4, commented, or hardcoded entries."
            )

            expected_calls = collections.Counter(
                message
                for mount in mounts
                for message in [f"VERIFIED: {mount}"] * 12
            )
            assert collections.Counter(observed["info_calls"]) == expected_calls, (
                "The script must call logger.info() exactly 12 times with the exact message "
                "for every ext4 mount point."
            )

            expected_bases = {
                os.path.abspath(os.path.join(logs_dir, mount.replace("/", "_") + ".log"))
                for mount in mounts
            }
            handler_data = observed["handlers"]
            assert {item["baseFilename"] for item in handler_data} == expected_bases, (
                "A RotatingFileHandler was not configured for exactly the parsed ext4 mounts."
            )
            assert len(handler_data) == len(mounts)
            for item in handler_data:
                assert item["maxBytes"] == 60, "RotatingFileHandler maxBytes must be 60."
                assert item["backupCount"] == 2, "RotatingFileHandler backupCount must be 2."
                assert item["formatted"] == "FORMAT_SENTINEL", (
                    "The log formatter must output only the message."
                )
        finally:
            with open(fstab, "wb") as f:
                f.write(old_fstab)
            if os.path.exists(logs_dir):
                shutil.rmtree(logs_dir)
            shutil.copytree(logs_backup, logs_dir)
            if old_summary_exists:
                with open(summary_path, "wb") as f:
                    f.write(old_summary)
            elif os.path.exists(summary_path):
                os.unlink(summary_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
