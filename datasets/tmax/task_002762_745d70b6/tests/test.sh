#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import io
import os
import runpy
import subprocess
import sys
import tarfile
import uuid
import zipfile

import pytest

SCRIPT_PATH = "/home/user/scan_logs.py"
LOG_PATH = "/home/user/found_errors.log"
ARCHIVE_ROOT = "/home/user/archive_mess"


def run_script(block_extraction=False):
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    if not block_extraction:
        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
    else:
        runner = r'''
import runpy
import tarfile
import zipfile

def forbidden(*args, **kwargs):
    raise AssertionError("Archives must be processed in memory, not extracted to disk")

tarfile.TarFile.extract = forbidden
tarfile.TarFile.extractall = forbidden
zipfile.ZipFile.extract = forbidden
zipfile.ZipFile.extractall = forbidden
runpy.run_path("/home/user/scan_logs.py", run_name="__main__")
'''
        result = subprocess.run(
            [sys.executable, "-c", runner],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )

    assert result.returncode == 0, (
        f"scan_logs.py did not execute successfully.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def read_output():
    # Preserve the original existence and regular-file assertions.
    assert os.path.exists(LOG_PATH), f"The output log file was not found: {LOG_PATH}"
    assert os.path.isfile(LOG_PATH), f"The path {LOG_PATH} is not a file."
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        return f.readlines()


def derive_expected():
    expected = []
    for root, _, files in os.walk(ARCHIVE_ROOT):
        for filename in files:
            if not filename.endswith(".tar"):
                continue
            tar_path = os.path.join(root, filename)
            with tarfile.open(tar_path, "r:*") as tf:
                for member in tf.getmembers():
                    if not member.isfile() or not member.name.endswith(".zip"):
                        continue
                    extracted = tf.extractfile(member)
                    assert extracted is not None
                    zip_bytes = extracted.read()
                    with zipfile.ZipFile(io.BytesIO(zip_bytes), "r") as zf:
                        for txt_name in zf.namelist():
                            if txt_name.endswith("/") or not txt_name.endswith(".txt"):
                                continue
                            text = zf.read(txt_name).decode("utf-8")
                            for line in text.splitlines(keepends=True):
                                if "ERROR_STATE_RACE_CONDITION" in line:
                                    expected.append(
                                        f"{filename} -> {member.name} -> {txt_name}: {line}"
                                    )
    return expected


def create_dynamic_archive():
    token = uuid.uuid4().hex
    nested_dir = os.path.join(ARCHIVE_ROOT, "deep", token)
    os.makedirs(nested_dir, exist_ok=True)
    tar_name = f"generated_{token}.tar"
    tar_path = os.path.join(nested_dir, tar_name)
    zip_name = f"runtime_{token}.zip"
    txt_names = [f"alpha_{token}.txt", f"beta_{token}.txt"]

    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(
            txt_names[0],
            f"ordinary runtime line {token}\n"
            f"{token} ERROR_STATE_RACE_CONDITION first dynamic match\n",
        )
        zf.writestr(
            txt_names[1],
            f"{token} ERROR_STATE_RACE_CONDITION second dynamic match\n"
            "unrelated final line\n",
        )
        zf.writestr(f"ignored_{token}.bin", "ERROR_STATE_RACE_CONDITION\n")

    payload = zip_buffer.getvalue()
    with tarfile.open(tar_path, "w") as tf:
        info = tarfile.TarInfo(zip_name)
        info.size = len(payload)
        tf.addfile(info, io.BytesIO(payload))
        decoy = b"ERROR_STATE_RACE_CONDITION\n"
        info = tarfile.TarInfo(f"not_a_zip_{token}.dat")
        info.size = len(decoy)
        tf.addfile(info, io.BytesIO(decoy))

    return zip_name, txt_names


def test_complete_task():
    # Preserve the original script existence assertions and verify it is Python.
    assert os.path.exists(SCRIPT_PATH), f"The script file was not found: {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        ast.parse(f.read(), filename=SCRIPT_PATH)

    # Execute the submitted artifact and preserve the original exact comparison.
    run_script()
    expected_lines = [
        "bundle1.tar -> logsA.zip -> app2.txt: 2023-10-05 - ERROR_STATE_RACE_CONDITION in db_lock\n",
        "bundle2.tar -> logsB.zip -> app3.txt: 2023-10-06 - ERROR_STATE_RACE_CONDITION during cache flush\n",
    ]
    actual_lines = read_output()
    assert sorted(actual_lines) == sorted(expected_lines), (
        f"The contents of {LOG_PATH} do not match the expected output.\n"
        f"Expected:\n{sorted(expected_lines)}\nActual:\n{sorted(actual_lines)}"
    )

    # Add an unpredictable archive below a nested directory, then rerun while
    # disabling the standard archive-to-disk extraction APIs.
    zip_name, txt_names = create_dynamic_archive()
    run_script(block_extraction=True)
    expected_dynamic = derive_expected()
    actual_dynamic = read_output()
    assert sorted(actual_dynamic) == sorted(expected_dynamic), (
        "The script did not recursively scan and process the runtime-generated "
        "tar/zip/text contents correctly.\n"
        f"Expected:\n{sorted(expected_dynamic)}\nActual:\n{sorted(actual_dynamic)}"
    )

    # Standard extraction must not have left inner archive members on disk.
    forbidden_names = {zip_name, *txt_names}
    for search_root in ("/home/user", "/tmp"):
        for root, _, files in os.walk(search_root):
            for name in files:
                assert name not in forbidden_names, (
                    f"Archive member was extracted to disk: {os.path.join(root, name)}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
