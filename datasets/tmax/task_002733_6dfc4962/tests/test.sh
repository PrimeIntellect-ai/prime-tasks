#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import shutil
import struct
import subprocess
import tempfile
import zipfile
from pathlib import Path

import pytest

REPORT_FILE = "/home/user/anomaly_report.json"
DATASET_DIR = "/home/user/datasets"
SIGNATURE = b"ANOMALY_778"


def test_report_file_exists():
    assert os.path.exists(REPORT_FILE), f"The report file {REPORT_FILE} was not created."
    assert os.path.isfile(REPORT_FILE), f"{REPORT_FILE} is not a valid file."


def test_report_file_content():
    assert os.path.exists(REPORT_FILE), f"Cannot check content, {REPORT_FILE} missing."

    try:
        with open(REPORT_FILE, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {REPORT_FILE} does not contain valid JSON.")
    except Exception as e:
        pytest.fail(f"Failed to read {REPORT_FILE}: {e}")

    expected = {
        "data_01.zip": [1024, 4096],
        "data_03.zip": [2048],
        "data_05.zip": [],
    }

    assert data == expected, (
        f"The contents of {REPORT_FILE} do not match the expected output.\n"
        f"Expected: {expected}\n"
        f"Got: {data}"
    )


def _candidate_scripts():
    candidates = []
    for root in ("/home/user", "/tmp"):
        for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
            dirnames[:] = [d for d in dirnames if d not in {"__pycache__", ".cache"}]
            for filename in filenames:
                if not filename.endswith(".py"):
                    continue
                path = os.path.join(dirpath, filename)
                if path == "/tmp/test_final_state.py" or "verifier_audit" in path:
                    continue
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    source = Path(path).read_text(encoding="utf-8")
                    tree = ast.parse(source)
                except Exception:
                    continue

                imported = set()
                for node in ast.walk(tree):
                    if isinstance(node, ast.Import):
                        imported.update(alias.name.split(".")[0] for alias in node.names)
                    elif isinstance(node, ast.ImportFrom) and node.module:
                        imported.add(node.module.split(".")[0])

                # These modules are explicitly required by the task. Runtime audit
                # checks below ensure tempfile and mmap are actually exercised.
                if {"zipfile", "tempfile", "mmap"}.issubset(imported):
                    candidates.append(path)
    return sorted(set(candidates))


def _offsets(data):
    result = []
    start = 0
    while True:
        pos = data.find(SIGNATURE, start)
        if pos < 0:
            return result
        result.append(pos)
        start = pos + 1


def _write_valid_zip(path, payload):
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as zf:
        zf.writestr("measurements.bin", payload)


def _make_bad_crc_zip(path, payload):
    _write_valid_zip(path, payload)
    raw = bytearray(Path(path).read_bytes())
    assert raw[:4] == b"PK\x03\x04"
    name_len, extra_len = struct.unpack_from("<HH", raw, 26)
    data_start = 30 + name_len + extra_len
    raw[data_start] ^= 0xFF
    Path(path).write_bytes(raw)


def _remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def test_script_executes_required_workflow_on_unseen_archives():
    candidates = _candidate_scripts()
    assert candidates, (
        "No Python script using zipfile, tempfile, and mmap was found under "
        "/home/user or /tmp."
    )

    work = tempfile.mkdtemp(prefix="verifier_dynamic_")
    original_datasets = os.path.join(work, "original_datasets")
    pristine = os.path.join(work, "pristine")
    audit_dir = os.path.join(work, "verifier_audit")
    original_report = Path(REPORT_FILE).read_bytes()
    errors = []

    try:
        os.rename(DATASET_DIR, original_datasets)
        os.makedirs(DATASET_DIR, mode=0o777)

        token = secrets.token_hex(6)
        payloads = {
            f"field_{token}_a.zip": b"A" * 317 + SIGNATURE + b"B" * 911 + SIGNATURE + b"C" * 23,
            f"field_{token}_b.zip": b"no anomaly here" * 173,
            f"field_{token}_c.zip": b"Q" * 73 + SIGNATURE + b"R" * 2049,
        }
        expected = {}
        for name, payload in payloads.items():
            _write_valid_zip(os.path.join(DATASET_DIR, name), payload)
            expected[name] = _offsets(payload)

        Path(os.path.join(DATASET_DIR, f"garbage_{token}.zip")).write_bytes(
            b"not a zip archive"
        )
        truncated = os.path.join(DATASET_DIR, f"truncated_{token}.zip")
        _write_valid_zip(truncated, b"X" * 300 + SIGNATURE)
        raw = Path(truncated).read_bytes()
        Path(truncated).write_bytes(raw[: max(20, len(raw) // 2)])
        _make_bad_crc_zip(
            os.path.join(DATASET_DIR, f"bad_crc_{token}.zip"),
            b"Y" * 500 + SIGNATURE + b"Z" * 100,
        )

        shutil.copytree(DATASET_DIR, pristine)
        os.makedirs(audit_dir)
        sitecustomize = r'''
import json
import os
import sys

_log = os.environ.get("VERIFIER_AUDIT_LOG")

def _record(item):
    try:
        fd = os.open(_log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
        try:
            os.write(fd, (json.dumps(item) + "\\n").encode("utf-8"))
        finally:
            os.close(fd)
    except Exception:
        pass

def _hook(event, args):
    if event == "mmap.__new__":
        _record(["MMAP"])
    elif event == "tempfile.mkdtemp":
        _record(["TEMP", os.fsdecode(args[0])])
    elif event == "os.rename":
        try:
            _record(["RENAME", os.fsdecode(args[0]), os.fsdecode(args[1])])
        except Exception:
            _record(["RENAME", repr(args[0]), repr(args[1])])

sys.addaudithook(_hook)
'''
        Path(os.path.join(audit_dir, "sitecustomize.py")).write_text(
            sitecustomize, encoding="utf-8"
        )

        for script in candidates:
            _remove_path(DATASET_DIR)
            shutil.copytree(pristine, DATASET_DIR)
            if os.path.lexists(REPORT_FILE):
                _remove_path(REPORT_FILE)

            audit_log = os.path.join(work, "audit.log")
            if os.path.exists(audit_log):
                os.unlink(audit_log)
            env = os.environ.copy()
            env["PYTHONPATH"] = audit_dir + os.pathsep + env.get("PYTHONPATH", "")
            env["VERIFIER_AUDIT_LOG"] = audit_log

            try:
                proc = subprocess.run(
                    ["python3", script],
                    cwd="/home/user",
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
            except Exception as exc:
                errors.append(f"{script}: execution failed: {exc}")
                continue

            if proc.returncode != 0:
                errors.append(f"{script}: exited {proc.returncode}: {proc.stderr[-500:]}")
                continue

            try:
                with open(REPORT_FILE, "r", encoding="utf-8") as f:
                    actual = json.load(f)
            except Exception as exc:
                errors.append(f"{script}: did not create valid JSON: {exc}")
                continue
            if actual != expected:
                errors.append(f"{script}: dynamic report was {actual!r}, expected {expected!r}")
                continue

            events = []
            try:
                with open(audit_log, "r", encoding="utf-8") as f:
                    events = [json.loads(line) for line in f if line.strip()]
            except Exception as exc:
                errors.append(f"{script}: audit log unavailable: {exc}")
                continue

            mmap_count = sum(event[0] == "MMAP" for event in events)
            temp_dirs = {event[1] for event in events if event[0] == "TEMP"}
            atomic_writes = [
                event for event in events
                if event[0] == "RENAME"
                and os.path.abspath(event[2]) == REPORT_FILE
                and os.path.abspath(event[1]) != REPORT_FILE
            ]

            if mmap_count < len(payloads):
                errors.append(f"{script}: mmap was not used for every valid archive")
                continue
            if len(temp_dirs) < len(payloads):
                errors.append(f"{script}: no separate tempfile directory was used per valid archive")
                continue
            uncleared = [path for path in temp_dirs if os.path.exists(path)]
            if uncleared:
                errors.append(f"{script}: temporary directories were not cleaned: {uncleared}")
                continue
            if not atomic_writes:
                errors.append(f"{script}: report was not installed with an atomic rename/replace")
                continue

            return

        pytest.fail("No submitted script passed execution and workflow checks:\n" + "\n".join(errors))
    finally:
        if os.path.lexists(DATASET_DIR):
            _remove_path(DATASET_DIR)
        if os.path.exists(original_datasets):
            os.rename(original_datasets, DATASET_DIR)
        if os.path.lexists(REPORT_FILE):
            _remove_path(REPORT_FILE)
        Path(REPORT_FILE).write_bytes(original_report)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
