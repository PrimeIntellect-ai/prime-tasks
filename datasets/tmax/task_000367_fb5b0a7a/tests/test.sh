#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import json
import os
import subprocess
import sys
import pytest

ARCHIVE = "/home/user/backup/archive.jsonl"
CRITERIA = "/home/user/dataset/criteria.ini"
LOG = "/home/user/dataset/instrument.log"


def test_archive_jsonl_final_state():
    archive_file = ARCHIVE
    assert os.path.isfile(archive_file), f"File {archive_file} is missing."

    expected_records = [
        {"RecordID": "101", "Date": "2023-11-01", "SensorType": "Temperature", "Value": 15.2},
        {"RecordID": "099", "Date": "2023-10-31", "SensorType": "Humidity", "Value": 50.1},
        {"RecordID": "103", "Date": "2023-11-02", "SensorType": "Humidity", "Value": 45.0},
        {"RecordID": "105", "Date": "2023-11-03", "SensorType": "Radiation", "Value": 12.1},
        {"RecordID": "106", "Date": "2023-11-03", "SensorType": "Temperature", "Value": 22.4}
    ]

    actual_records = []
    with open(archive_file, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual_records.append(record)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {archive_file} is not valid JSON: {line}")

    assert len(actual_records) == len(expected_records), (
        f"Expected {len(expected_records)} records in {archive_file}, but found {len(actual_records)}. "
        f"Actual records: {actual_records}"
    )

    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        assert actual == expected, (
            f"Record at line {i+1} does not match expected.\n"
            f"Expected: {expected}\n"
            f"Actual: {actual}"
        )


def test_input_files_unmodified():
    criteria_file = CRITERIA
    log_file = LOG

    assert os.path.isfile(criteria_file), "criteria.ini was deleted."
    assert os.path.isfile(log_file), "instrument.log was deleted."

    with open(criteria_file, 'r') as f:
        criteria_content = f.read()
    assert "valid_sensors = Temperature, Humidity, Radiation" in criteria_content, "criteria.ini was modified."
    assert "min_value = 10.5" in criteria_content, "criteria.ini was modified."

    with open(log_file, 'r') as f:
        log_content = f.read()
    assert "RecordID: 101" in log_content and "RecordID: 106" in log_content, "instrument.log was modified."


def _discover_python_scripts():
    excluded = {
        os.path.realpath(__file__),
        os.path.realpath(ARCHIVE),
        os.path.realpath(CRITERIA),
        os.path.realpath(LOG),
    }
    candidates = []
    for root in ("/home/user", "/tmp"):
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {"__pycache__", ".pytest_cache", ".cache", "site-packages"}]
            for name in files:
                path = os.path.join(directory, name)
                real = os.path.realpath(path)
                if real in excluded or not os.path.isfile(path):
                    continue
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    with open(path, "rb") as f:
                        raw = f.read()
                    if b"\x00" in raw:
                        continue
                    source = raw.decode("utf-8")
                    compile(source, path, "exec")
                except (OSError, UnicodeDecodeError, SyntaxError):
                    continue
                candidates.append(path)
    return sorted(set(candidates))


def _derive_expected(criteria_bytes, log_bytes, archive_prefix):
    parser = configparser.ConfigParser()
    parser.read_string(criteria_bytes.decode("utf-8"))
    valid_sensors = {x.strip() for x in parser["Filters"]["valid_sensors"].split(",")}
    min_value = float(parser["Filters"]["min_value"])

    existing_ids = set()
    for line in archive_prefix.decode("utf-8").splitlines():
        if line.strip():
            existing_ids.add(str(json.loads(line)["RecordID"]))

    records = []
    current = {}
    for line in log_bytes.decode("utf-8").splitlines():
        if line == "---":
            if current:
                records.append(current)
                current = {}
        elif line and ": " in line:
            key, value = line.split(": ", 1)
            current[key] = value
    if current:
        records.append(current)

    expected = []
    for record in records:
        value = float(record["Value"])
        if (record["SensorType"] in valid_sensors and value > min_value
                and record["RecordID"] not in existing_ids):
            expected.append({
                "RecordID": record["RecordID"],
                "Date": record["Date"],
                "SensorType": record["SensorType"],
                "Value": value,
            })
            existing_ids.add(record["RecordID"])
    return expected


def _exercise(script, criteria_bytes, log_bytes, archive_prefix):
    with open(CRITERIA, "wb") as f:
        f.write(criteria_bytes)
    with open(LOG, "wb") as f:
        f.write(log_bytes)
    with open(ARCHIVE, "wb") as f:
        f.write(archive_prefix)

    expected = _derive_expected(criteria_bytes, log_bytes, archive_prefix)
    result = subprocess.run(
        [sys.executable, script], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8
    )
    assert result.returncode == 0, f"script exited {result.returncode}: {result.stderr[-1000:]}"

    with open(CRITERIA, "rb") as f:
        assert f.read() == criteria_bytes, "script modified criteria.ini"
    with open(LOG, "rb") as f:
        assert f.read() == log_bytes, "script modified instrument.log"
    with open(ARCHIVE, "rb") as f:
        after = f.read()

    assert after.startswith(archive_prefix), "existing archive bytes were modified instead of preserved"
    appended = after[len(archive_prefix):]
    lines = appended.splitlines(keepends=True)
    assert all(line.endswith(b"\n") for line in lines), "each appended JSON object must end with a newline"
    actual = [json.loads(line.decode("utf-8")) for line in lines if line.strip()]
    assert actual == expected, f"expected dynamically derived appended records {expected}, got {actual}"
    for record in actual:
        assert set(record) == {"RecordID", "Date", "SensorType", "Value"}
        assert isinstance(record["Value"], float)
        assert all(isinstance(record[k], str) for k in ("RecordID", "Date", "SensorType"))

    first_run = after
    result = subprocess.run(
        [sys.executable, script], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8
    )
    assert result.returncode == 0, f"second run exited {result.returncode}: {result.stderr[-1000:]}"
    with open(ARCHIVE, "rb") as f:
        assert f.read() == first_run, "running again duplicated or changed archived records"


def test_saved_script_executes_incremental_backup_on_changed_inputs():
    candidates = _discover_python_scripts()
    assert candidates, "No saved Python script was found."

    fixtures = [
        (
            b"[Filters]\nvalid_sensors = Salinity, Temperature\nmin_value = 5.5\n",
            b"---\nRecordID: old-7\nDate: 2040-01-01\nSensorType: Salinity\nValue: 90\n---\nRecordID: new-a\nDate: 2040-01-02\nSensorType: Salinity\nValue: 5.6\n---\nRecordID: equal\nDate: 2040-01-03\nSensorType: Temperature\nValue: 5.5\n---\nRecordID: wrong-sensor\nDate: 2040-01-04\nSensorType: Pressure\nValue: 500\n---\nRecordID: new-b\nDate: 2040-01-05\nSensorType: Temperature\nValue: 19.25\n",
            b'{  "RecordID" : "old-7", "Date" : "2039-12-31", "SensorType" : "Salinity", "Value" : 1.0 }\n'
        ),
        (
            b"[Filters]\nvalid_sensors = Radiation\nmin_value = -1.0\n",
            b"---\nRecordID: prior\nDate: 2050-02-01\nSensorType: Radiation\nValue: 100\n---\nRecordID: fresh\nDate: 2050-02-02\nSensorType: Radiation\nValue: -0.25\n---\nRecordID: excluded\nDate: 2050-02-03\nSensorType: Humidity\nValue: 80\n---\nRecordID: boundary\nDate: 2050-02-04\nSensorType: Radiation\nValue: -1.0\n",
            b'{"RecordID":"prior","Date":"2049-12-31","SensorType":"Radiation","Value":3.0}\n'
        )
    ]

    originals = {}
    for path in (CRITERIA, LOG, ARCHIVE):
        with open(path, "rb") as f:
            originals[path] = f.read()

    errors = []
    try:
        for script in candidates:
            try:
                for fixture in fixtures:
                    _exercise(script, *fixture)
                return
            except Exception as exc:
                errors.append(f"{script}: {type(exc).__name__}: {exc}")
    finally:
        for path, content in originals.items():
            with open(path, "wb") as f:
                f.write(content)

    pytest.fail("No saved Python script correctly processed dynamic fixtures:\n" + "\n".join(errors[-20:]))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
