#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import csv
import hashlib
import os
import re
import secrets
import subprocess
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path

import pytest

SCRIPT_PATH = Path("/home/user/cleaner.py")
RAW_PATH = Path("/home/user/raw_data.csv")
CLEAN_PATH = Path("/home/user/clean_data.csv")


def test_cleaner_script_exists():
    script_path = "/home/user/cleaner.py"
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."


def test_clean_data_content():
    clean_data_path = "/home/user/clean_data.csv"
    assert os.path.exists(clean_data_path), f"The output file {clean_data_path} does not exist."

    expected_content = """timestamp,sensor_id,value
2023-10-01T09:59:00,A,8.0
2023-10-01T10:00:00,A,10.0
2023-10-01T10:01:00,A,12.0
2023-10-01T10:02:00,A,14.0
2023-10-01T10:03:00,A,16.0
2023-10-01T10:04:00,A,18.0
2023-10-01T10:06:00,A,22.0"""

    with open(clean_data_path, "r") as f:
        content = f.read().strip()

    content = content.replace("\r\n", "\n")
    expected_content = expected_content.replace("\r\n", "\n")

    assert content == expected_content, "The content of clean_data.csv does not match the expected deduplicated, sorted, and interpolated data."


def test_cron_backup_exists_and_content():
    backup_path = "/home/user/cron_backup.txt"
    assert os.path.exists(backup_path), f"The cron backup file {backup_path} does not exist."

    with open(backup_path, "r") as f:
        content = f.read()

    pattern = r"^15\s+\*\s+\*\s+\*\s+\*\s+.*python3\s+/home/user/cleaner\.py$"
    match = any(re.match(pattern, line.strip()) for line in content.splitlines())
    assert match, "The cron_backup.txt does not contain the correct cron job entry."


def test_actual_crontab_entry():
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
        content = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read the current user's crontab.")

    pattern = r"^15\s+\*\s+\*\s+\*\s+\*\s+.*python3\s+/home/user/cleaner\.py$"
    match = any(re.match(pattern, line.strip()) for line in content.splitlines())
    assert match, "The actual crontab does not contain the correct cron job entry."


def reference_clean(raw_rows):
    deduplicated = []
    seen = set()
    for timestamp, sensor_id, value in raw_rows:
        source = f"{timestamp},{sensor_id},{value}"
        row_hash = hashlib.md5(source.encode("utf-8")).hexdigest()
        if row_hash not in seen:
            seen.add(row_hash)
            deduplicated.append({
                "timestamp": datetime.fromisoformat(timestamp),
                "sensor_id": sensor_id,
                "value": None if value == "" else float(value),
            })

    deduplicated.sort(key=lambda row: row["timestamp"])
    for index, row in enumerate(deduplicated):
        if row["value"] is not None:
            continue
        before = next((deduplicated[i] for i in range(index - 1, -1, -1)
                       if deduplicated[i]["value"] is not None), None)
        after = next((deduplicated[i] for i in range(index + 1, len(deduplicated))
                      if deduplicated[i]["value"] is not None), None)
        assert before is not None and after is not None
        elapsed = (row["timestamp"] - before["timestamp"]).total_seconds()
        span = (after["timestamp"] - before["timestamp"]).total_seconds()
        row["value"] = round(before["value"] + (after["value"] - before["value"]) * elapsed / span, 1)

    return [
        (row["timestamp"].strftime("%Y-%m-%dT%H:%M:%S"), row["sensor_id"], row["value"])
        for row in deduplicated
    ]


def test_script_executes_dynamic_pipeline_and_uses_md5(tmp_path):
    original_raw = RAW_PATH.read_bytes()
    original_clean = CLEAN_PATH.read_bytes() if CLEAN_PATH.exists() else None

    day = 10 + secrets.randbelow(10)
    hour = 3 + secrets.randbelow(12)
    base = datetime(2024, 2, day, hour, 0, 0)
    sensor = "sensor_" + secrets.token_hex(4)
    start = 10 + secrets.randbelow(30)

    def stamp(minutes):
        return (base + timedelta(minutes=minutes)).strftime("%Y-%m-%dT%H:%M:%S")

    # Irregular time gaps distinguish time interpolation from positional interpolation.
    raw_rows = [
        (stamp(20), sensor, f"{start + 28}.0"),
        (stamp(7), sensor, ""),
        (stamp(0), sensor, f"{start}.0"),
        (stamp(13), sensor, ""),
        (stamp(20), sensor, f"{start + 28}.0"),
        (stamp(7), sensor, ""),
    ]
    expected = reference_clean(raw_rows)

    fixture_lines = ["timestamp,sensor_id,value"] + [",".join(row) for row in raw_rows]
    fixture = "\n".join(fixture_lines) + "\n"

    hook_dir = tmp_path / "hook"
    hook_dir.mkdir()
    md5_log = tmp_path / "md5.log"
    (hook_dir / "sitecustomize.py").write_text(r'''
import base64
import hashlib
import os

_log_path = os.environ.get("CLEANER_MD5_LOG")
_real_md5 = hashlib.md5
_real_new = hashlib.new

class _TrackedMD5:
    def __init__(self, inner, initial=b""):
        self._inner = inner
        self._data = bytearray(initial)

    def update(self, data):
        self._data.extend(bytes(data))
        return self._inner.update(data)

    def _record(self):
        if _log_path:
            with open(_log_path, "ab") as log:
                log.write(base64.b64encode(bytes(self._data)) + b"\n")

    def hexdigest(self):
        self._record()
        return self._inner.hexdigest()

    def digest(self):
        self._record()
        return self._inner.digest()

    def copy(self):
        return _TrackedMD5(self._inner.copy(), bytes(self._data))

    def __getattr__(self, name):
        return getattr(self._inner, name)

def _tracked_md5(data=b"", *args, **kwargs):
    return _TrackedMD5(_real_md5(data, *args, **kwargs), bytes(data))

def _tracked_new(name, data=b"", **kwargs):
    inner = _real_new(name, data, **kwargs)
    if str(name).lower().replace("-", "") == "md5":
        return _TrackedMD5(inner, bytes(data))
    return inner

hashlib.md5 = _tracked_md5
hashlib.new = _tracked_new
''')

    try:
        RAW_PATH.write_text(fixture)
        if CLEAN_PATH.exists():
            CLEAN_PATH.unlink()

        env = os.environ.copy()
        env["PYTHONPATH"] = str(hook_dir)
        env["CLEANER_MD5_LOG"] = str(md5_log)
        result = subprocess.run(
            ["python3", str(SCRIPT_PATH)],
            cwd="/home/user",
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"cleaner.py failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
        assert CLEAN_PATH.is_file(), "Executing cleaner.py did not create clean_data.csv."

        with CLEAN_PATH.open(newline="") as output_file:
            reader = csv.DictReader(output_file)
            assert reader.fieldnames == ["timestamp", "sensor_id", "value"], "Output columns or their order are incorrect."
            actual_rows = list(reader)

        assert len(actual_rows) == len(expected), "Dynamic output was not correctly deduplicated."
        for actual, (expected_timestamp, expected_sensor, expected_value) in zip(actual_rows, expected):
            assert actual["timestamp"] == expected_timestamp, "Timestamps are not sorted/formatted as required."
            assert actual["sensor_id"] == expected_sensor
            assert re.fullmatch(r"-?\d+\.\d", actual["value"]), "Values must be rounded to one decimal place."
            assert float(actual["value"]) == pytest.approx(expected_value, abs=1e-9), "Time-based interpolation is incorrect."

        assert md5_log.exists(), "No MD5 hashing was observed while cleaner.py processed the input."
        observed_inputs = Counter(
            base64.b64decode(line).decode("utf-8")
            for line in md5_log.read_bytes().splitlines()
            if line
        )
        required_inputs = Counter(",".join(row) for row in raw_rows)
        for source, count in required_inputs.items():
            assert observed_inputs[source] >= count, (
                "Each original row, including rows with an empty value and duplicate rows, "
                "must be hashed as its exact comma-joined UTF-8 representation."
            )
    finally:
        RAW_PATH.write_bytes(original_raw)
        clean_env = os.environ.copy()
        clean_env.pop("PYTHONPATH", None)
        clean_env.pop("CLEANER_MD5_LOG", None)
        subprocess.run(["python3", str(SCRIPT_PATH)], cwd="/home/user", env=clean_env,
                       capture_output=True, text=True, timeout=30, check=False)
        if original_clean is not None and not CLEAN_PATH.exists():
            CLEAN_PATH.write_bytes(original_clean)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
