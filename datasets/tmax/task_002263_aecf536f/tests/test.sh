#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import signal
import subprocess
import tarfile
import xml.etree.ElementTree as ET

import pytest

TARBALL = "/home/user/incremental_backup.tar.gz"


def read_csv_member(tar, name):
    member = tar.getmember(name)
    assert member.isfile(), f"{name} must be a regular file."
    extracted = tar.extractfile(member)
    assert extracted is not None, f"Could not read {name}."
    return list(csv.reader(extracted.read().decode("utf-8").strip().splitlines()))


def test_tarball_exists():
    assert os.path.isfile(TARBALL), f"Tarball {TARBALL} does not exist. Did you create the archive?"


def test_tarball_contents():
    assert os.path.isfile(TARBALL), "Tarball missing."

    with tarfile.open(TARBALL, "r:gz") as tar:
        members = tar.getnames()

        # Check that the tarball contains exactly the expected files at the root
        assert "DS_001.csv" in members, "DS_001.csv is missing from the tarball root."
        assert "DS_003.csv" in members, "DS_003.csv is missing from the tarball root."
        assert "DS_002.csv" not in members, "DS_002.csv should not be in the tarball (it had FAILED status)."
        assert members.count("DS_001.csv") == 1
        assert members.count("DS_003.csv") == 1
        assert set(members) == {"DS_001.csv", "DS_003.csv"}, f"Unexpected archive members: {members}"

        # Check that no absolute paths or backup_staging directory are in the tarball
        for member in members:
            assert not member.startswith("/"), f"Archive contains absolute path: {member}"
            assert "backup_staging" not in member, f"Archive contains 'backup_staging' directory structure: {member}"


def test_csv_contents():
    assert os.path.isfile(TARBALL), "Tarball missing."

    with tarfile.open(TARBALL, "r:gz") as tar:
        ds1_rows = read_csv_member(tar, "DS_001.csv")
        assert len(ds1_rows) == 3, f"Expected 3 rows in DS_001.csv (1 header, 2 data), found {len(ds1_rows)}"
        assert ds1_rows[0] == ["id", "measurement", "sensor"], f"Incorrect header in DS_001.csv: {ds1_rows[0]}"
        assert ds1_rows[1] == ["101", "42.5", "alpha"], f"Incorrect data row 1 in DS_001.csv: {ds1_rows[1]}"
        assert ds1_rows[2] == ["102", "43.1", "alpha"], f"Incorrect data row 2 in DS_001.csv: {ds1_rows[2]}"

        ds3_rows = read_csv_member(tar, "DS_003.csv")
        assert len(ds3_rows) == 3, f"Expected 3 rows in DS_003.csv (1 header, 2 data), found {len(ds3_rows)}"
        assert ds3_rows[0] == ["id", "measurement", "sensor"], f"Incorrect header in DS_003.csv: {ds3_rows[0]}"
        assert ds3_rows[1] == ["301", "99.9", "beta"], f"Incorrect data row 1 in DS_003.csv: {ds3_rows[1]}"
        assert ds3_rows[2] == ["302", "100.1", "beta"], f"Incorrect data row 2 in DS_003.csv: {ds3_rows[2]}"


def find_python_scripts():
    scripts = []
    roots = ["/home/user", "/root", "/workspace", "/tmp"]
    excluded_dirs = {".git", "__pycache__", ".cache", "site-packages", "dist-packages", "backup_staging"}
    excluded_files = {os.path.realpath(__file__)}

    for root in roots:
        if not os.path.isdir(root):
            continue
        root_depth = root.rstrip(os.sep).count(os.sep)
        for current, dirs, files in os.walk(root, followlinks=False):
            depth = current.rstrip(os.sep).count(os.sep) - root_depth
            dirs[:] = [d for d in dirs if d not in excluded_dirs and not os.path.islink(os.path.join(current, d))]
            if depth >= 4:
                dirs[:] = []
            for filename in files:
                if not filename.lower().endswith(".py"):
                    continue
                path = os.path.realpath(os.path.join(current, filename))
                if path in excluded_files or not os.path.isfile(path) or os.path.islink(os.path.join(current, filename)):
                    continue
                try:
                    with open(path, "rb") as handle:
                        source = handle.read()
                    compile(source, path, "exec")
                except (OSError, SyntaxError, UnicodeError):
                    continue
                scripts.append(path)
    return sorted(set(scripts))


def reset_dynamic_fixture(success_json, success_xml, failed_id, json_records, xml_records):
    for path in ["/home/user/research_data", "/home/user/raw_storage", "/home/user/backup_staging"]:
        if os.path.lexists(path):
            if os.path.islink(path) or os.path.isfile(path):
                os.unlink(path)
            else:
                shutil.rmtree(path)
    if os.path.lexists(TARBALL):
        os.unlink(TARBALL)

    os.makedirs(f"/home/user/research_data/{success_json}")
    os.makedirs(f"/home/user/research_data/{success_xml}")
    os.makedirs(f"/home/user/research_data/{failed_id}")
    os.makedirs("/home/user/raw_storage")

    with open(f"/home/user/research_data/{success_json}/observations.json", "w", encoding="utf-8") as handle:
        json.dump(json_records, handle)

    xml_path = "/home/user/raw_storage/dynamic_records.xml"
    root = ET.Element("dataset")
    for row in xml_records:
        record = ET.SubElement(root, "record")
        for key, value in row.items():
            ET.SubElement(record, key).text = str(value)
    ET.ElementTree(root).write(xml_path, encoding="utf-8", xml_declaration=False)
    os.symlink(xml_path, f"/home/user/research_data/{success_xml}/observations.xml")

    with open(f"/home/user/research_data/{failed_id}/ignored.json", "w", encoding="utf-8") as handle:
        json.dump([{"id": 999, "value": "must not be archived"}], handle)

    # Cyclic directory links ensure unsafe traversal hangs until the verifier timeout.
    os.symlink(f"/home/user/research_data/{success_json}", f"/home/user/research_data/{success_json}/loop_dir")
    os.symlink(f"/home/user/research_data/{success_xml}", f"/home/user/research_data/{success_xml}/loop_dir")

    with open("/home/user/dataset_updates.log", "w", encoding="utf-8") as handle:
        handle.write(
            f"[2026-09-11 09:00:00]\nDataset: {failed_id}\nStatus: FAILED\nDetails: Ignore this dataset.\n\n"
            f"[2026-09-11 09:01:00]\nDataset: {success_xml}\nStatus: SUCCESS\nDetails: XML update.\n\n"
            f"[2026-09-11 09:02:00]\nDataset: {success_json}\nStatus: SUCCESS\nDetails: JSON update.\n"
        )


def execute_with_timeout(script):
    process = subprocess.Popen(
        ["python3", script],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=8)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
        return False, f"timed out (possible cyclic-symlink traversal); stdout={stdout!r}, stderr={stderr!r}"
    return process.returncode == 0, f"exit={process.returncode}; stdout={stdout!r}; stderr={stderr!r}"


def validate_dynamic_archive(success_json, success_xml, failed_id, json_records, xml_records):
    if not os.path.isfile(TARBALL):
        return False, "tarball was not created"
    try:
        with tarfile.open(TARBALL, "r:gz") as tar:
            names = tar.getnames()
            expected_names = {f"{success_json}.csv", f"{success_xml}.csv"}
            if set(names) != expected_names or len(names) != 2:
                return False, f"expected exactly {sorted(expected_names)}, got {names}"
            if f"{failed_id}.csv" in names:
                return False, "failed dataset was archived"
            for name in names:
                if name.startswith("/") or "/" in name or "backup_staging" in name:
                    return False, f"member is not at archive root: {name}"
                if not tar.getmember(name).isfile():
                    return False, f"member is not a regular file: {name}"

            json_rows = read_csv_member(tar, f"{success_json}.csv")
            xml_rows = read_csv_member(tar, f"{success_xml}.csv")
            expected_json = [list(json_records[0].keys())] + [[str(row[k]) for k in json_records[0].keys()] for row in json_records]
            expected_xml = [list(xml_records[0].keys())] + [[str(row[k]) for k in xml_records[0].keys()] for row in xml_records]
            if json_rows != expected_json:
                return False, f"JSON conversion mismatch: expected {expected_json}, got {json_rows}"
            if xml_rows != expected_xml:
                return False, f"XML conversion mismatch: expected {expected_xml}, got {xml_rows}"
    except Exception as exc:
        return False, f"invalid archive: {exc}"
    return True, "ok"


def test_written_python_script_executes_and_handles_dynamic_inputs():
    scripts = find_python_scripts()
    assert scripts, "No Python script was written for the backup task."

    token = secrets.randbelow(800000) + 100000
    success_json = f"DS_{token}"
    success_xml = f"DS_{token + 1}"
    failed_id = f"DS_{token + 2}"
    json_records = [
        {"id": token, "value": "fresh, json", "note": "generated at verification"},
        {"id": token + 10, "value": "second", "note": "not fixture data"},
    ]
    xml_records = [
        {"id": token + 20, "value": "fresh XML", "note": "linked target"},
        {"id": token + 30, "value": "another", "note": "safe traversal"},
    ]

    failures = []
    for script in scripts:
        reset_dynamic_fixture(success_json, success_xml, failed_id, json_records, xml_records)
        ran, detail = execute_with_timeout(script)
        if not ran:
            failures.append(f"{script}: {detail}")
            continue
        valid, detail = validate_dynamic_archive(success_json, success_xml, failed_id, json_records, xml_records)
        if valid:
            return
        failures.append(f"{script}: {detail}")

    pytest.fail("No written Python script correctly performed the dynamic backup. " + " | ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
