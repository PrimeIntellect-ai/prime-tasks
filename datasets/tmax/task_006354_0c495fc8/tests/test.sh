#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import io
import json
import time
import uuid
import shutil
import fcntl
import subprocess
import pytest

INVENTORY_FILE = "/home/user/inventory.jsonl"
EXTRACTED_DIR = "/home/user/extracted_assets"
SCRIPT_FILE = "/home/user/organize_docs.py"
ARCHIVE_DIR = "/home/user/doc_archive"


def clean_outputs():
    if os.path.lexists(INVENTORY_FILE):
        os.unlink(INVENTORY_FILE)
    if os.path.lexists(EXTRACTED_DIR):
        if os.path.isdir(EXTRACTED_DIR) and not os.path.islink(EXTRACTED_DIR):
            shutil.rmtree(EXTRACTED_DIR)
        else:
            os.unlink(EXTRACTED_DIR)


def load_inventory():
    records = []
    with open(INVENTORY_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            records.append(json.loads(line))
    return records


def test_00_execute_script_on_unseen_recursive_archive_and_observe_locking():
    assert os.path.isfile(SCRIPT_FILE), f"Script file {SCRIPT_FILE} does not exist."

    token = uuid.uuid4().hex
    backup_dir = f"/home/user/.doc_archive_verifier_{token}"
    report_file = f"/tmp/flock_report_{token}.json"
    deep_dir = os.path.join(ARCHIVE_DIR, f"level_{token}", "deeper", "assets")
    title = f"Generated title {token}"
    author = f"Generated author {token}"
    payload = os.urandom(41)
    xml_path = os.path.join(deep_dir, f"page_{token}.xml")
    json_path = os.path.join(deep_dir, f"metadata_{token}.json")
    valid_blob_path = os.path.join(deep_dir, f"asset_{token}.blob")
    invalid_blob_path = os.path.join(deep_dir, f"invalid_{token}.blob")
    dat_path = os.path.join(EXTRACTED_DIR, f"asset_{token}.dat")
    invalid_dat_path = os.path.join(EXTRACTED_DIR, f"invalid_{token}.dat")

    expected = [
        {"file": xml_path, "type": "xml", "title": title},
        {"file": json_path, "type": "json", "author": author},
        {"file": valid_blob_path, "type": "blob", "status": "extracted"},
    ]

    proc = None
    lock_file = None
    dynamic_ok = False
    os.rename(ARCHIVE_DIR, backup_dir)
    try:
        os.makedirs(deep_dir)
        with open(xml_path, "w") as f:
            f.write(f"<doc><header><title>{title}</title></header><body>dynamic</body></doc>")
        with open(json_path, "w") as f:
            json.dump({"author": author, "nonce": token}, f)
        with open(valid_blob_path, "wb") as f:
            f.write(b"DOCBLOB1" + payload)
        with open(invalid_blob_path, "wb") as f:
            f.write(b"NOTBLOB!" + os.urandom(19))

        clean_outputs()
        lock_file = open(INVENTORY_FILE, "w+")
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

        wrapper = r'''
import atexit, fcntl, json, os, runpy
original_flock = fcntl.flock
events = []
def tracked_flock(fd, operation):
    events.append(operation)
    return original_flock(fd, operation)
fcntl.flock = tracked_flock
def save_report():
    with open(os.environ["VERIFY_FLOCK_REPORT"], "w") as report:
        json.dump(events, report)
atexit.register(save_report)
runpy.run_path(os.environ["VERIFY_SCRIPT"], run_name="__main__")
'''
        env = os.environ.copy()
        env["VERIFY_FLOCK_REPORT"] = report_file
        env["VERIFY_SCRIPT"] = SCRIPT_FILE
        proc = subprocess.Popen(
            ["python3", "-c", wrapper],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        observed_kernel_lock_wait = False
        deadline = time.time() + 5
        while time.time() < deadline and proc.poll() is None:
            try:
                with open(f"/proc/{proc.pid}/wchan", "r") as f:
                    wchan = f.read().strip().lower()
                if "lock" in wchan:
                    observed_kernel_lock_wait = True
                    break
            except FileNotFoundError:
                break
            time.sleep(0.05)

        assert observed_kernel_lock_wait, "The running script did not block in the kernel while another process held the inventory flock."
        assert proc.poll() is None, "The script completed despite another process holding the exclusive inventory lock."
        assert os.path.getsize(INVENTORY_FILE) == 0, "The script wrote inventory data without first obtaining the exclusive lock."

        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()
        lock_file = None
        stdout, stderr = proc.communicate(timeout=15)
        assert proc.returncode == 0, f"Script failed on generated archive. stdout={stdout!r}, stderr={stderr!r}"
        proc = None

        assert os.path.isfile(report_file), "The script execution did not produce the flock trace."
        with open(report_file, "r") as f:
            flock_events = json.load(f)
        exclusive_calls = sum(1 for op in flock_events if (op & fcntl.LOCK_EX) == fcntl.LOCK_EX)
        assert exclusive_calls >= len(expected), "The script did not request an exclusive flock for each generated inventory record."

        assert os.path.isfile(INVENTORY_FILE)
        actual = load_inventory()
        assert sorted(actual, key=lambda x: x["file"]) == sorted(expected, key=lambda x: x["file"])
        assert os.path.isfile(dat_path)
        with open(dat_path, "rb") as f:
            assert f.read() == payload
        assert not os.path.exists(invalid_dat_path)
        dynamic_ok = True
    finally:
        if lock_file is not None:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            lock_file.close()
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.communicate()
        if os.path.lexists(ARCHIVE_DIR):
            shutil.rmtree(ARCHIVE_DIR)
        os.rename(backup_dir, ARCHIVE_DIR)
        clean_outputs()
        if os.path.exists(report_file):
            os.unlink(report_file)

    if dynamic_ok:
        result = subprocess.run(
            ["python3", SCRIPT_FILE],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"Script failed on the supplied archive. stdout={result.stdout!r}, stderr={result.stderr!r}"


def test_inventory_file_exists_and_contents():
    assert os.path.isfile(INVENTORY_FILE), f"Inventory file {INVENTORY_FILE} does not exist."

    expected_records = [
        {"file": os.path.join(ARCHIVE_DIR, "module1/intro.xml"), "type": "xml", "title": "Introduction to System"},
        {"file": os.path.join(ARCHIVE_DIR, "module1/meta.json"), "type": "json", "author": "Jane Doe"},
        {"file": os.path.join(ARCHIVE_DIR, "module1/textdata.blob"), "type": "blob", "status": "extracted"},
        {"file": os.path.join(ARCHIVE_DIR, "module2/advanced.xml"), "type": "xml", "title": "Advanced Configuration"},
        {"file": os.path.join(ARCHIVE_DIR, "module2/info.json"), "type": "json", "author": "John Smith"},
        {"file": os.path.join(ARCHIVE_DIR, "module2/assets/graphic1.blob"), "type": "blob", "status": "extracted"}
    ]

    actual_records = []
    with open(INVENTORY_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                actual_records.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON line in {INVENTORY_FILE}: {line}")

    assert len(actual_records) == len(expected_records), f"Expected {len(expected_records)} records, found {len(actual_records)}"
    actual_records.sort(key=lambda x: x.get("file", ""))
    expected_records.sort(key=lambda x: x.get("file", ""))
    for expected, actual in zip(expected_records, actual_records):
        assert expected == actual, f"Record mismatch. Expected: {expected}, Actual: {actual}"


def test_extracted_assets():
    assert os.path.isdir(EXTRACTED_DIR), f"Directory {EXTRACTED_DIR} does not exist."
    graphic1_dat = os.path.join(EXTRACTED_DIR, "graphic1.dat")
    textdata_dat = os.path.join(EXTRACTED_DIR, "textdata.dat")
    assert os.path.isfile(graphic1_dat), f"Extracted file {graphic1_dat} missing."
    assert os.path.isfile(textdata_dat), f"Extracted file {textdata_dat} missing."
    graphic2_dat = os.path.join(EXTRACTED_DIR, "graphic2.dat")
    assert not os.path.exists(graphic2_dat), f"File {graphic2_dat} should not have been extracted."
    with open(graphic1_dat, "rb") as f:
        assert f.read() == b"\xAA\xBB\xCC\xDD", f"Content of {graphic1_dat} is incorrect."
    with open(textdata_dat, "rb") as f:
        assert f.read() == b"PAYLOAD_DATA_HERE", f"Content of {textdata_dat} is incorrect."


def test_script_uses_file_locking():
    assert os.path.isfile(SCRIPT_FILE), f"Script file {SCRIPT_FILE} does not exist."
    with open(SCRIPT_FILE, "r") as f:
        content = f.read()
    assert "fcntl.flock" in content, f"Script {SCRIPT_FILE} does not appear to use fcntl.flock for file locking."
    assert "fcntl.LOCK_EX" in content, f"Script {SCRIPT_FILE} does not appear to use fcntl.LOCK_EX."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
