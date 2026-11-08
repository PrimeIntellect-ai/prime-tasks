#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import struct
import subprocess
import sys
import uuid
from pathlib import Path

import pytest

OUTBOX_DIR = "/home/user/project_outbox"
SECURITY_LOG = "/home/user/security.log"
SCRIPT_PATH = "/home/user/unpack.py"
ARCHIVE_PATH = "/home/user/archives/data.binpack"


def test_script_exists_and_uses_mmap():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        content = f.read()
    assert "mmap" in content, "The script must use the 'mmap' module as per requirements."


def test_valid_files_extracted_with_correct_encoding():
    info_txt_path = os.path.join(OUTBOX_DIR, "docs/info.txt")
    assert os.path.isfile(info_txt_path), f"Valid file {info_txt_path} was not extracted."

    with open(info_txt_path, "rb") as f:
        content_bytes = f.read()

    try:
        content_str = content_bytes.decode("utf-8")
    except UnicodeDecodeError:
        pytest.fail(f"File {info_txt_path} is not valid UTF-8.")

    assert content_str == "Project start: © 2023", f"Content of {info_txt_path} does not match expected UTF-8 output."

    main_py_path = os.path.join(OUTBOX_DIR, "src/main.py")
    assert os.path.isfile(main_py_path), f"Valid file {main_py_path} was not extracted."

    with open(main_py_path, "rb") as f:
        content_bytes = f.read()

    try:
        content_str = content_bytes.decode("utf-8")
    except UnicodeDecodeError:
        pytest.fail(f"File {main_py_path} is not valid UTF-8.")

    assert content_str == "print('Hello äöü')", f"Content of {main_py_path} does not match expected UTF-8 output."


def test_zip_slip_prevention():
    ssh_key_path = "/home/user/.ssh/authorized_keys"
    config_path = "/home/user/config.json"

    assert not os.path.exists(ssh_key_path), f"Zip-slip vulnerability triggered! File written to {ssh_key_path}"
    assert not os.path.exists(config_path), f"Zip-slip vulnerability triggered! File written to {config_path}"


def test_security_log_contents():
    assert os.path.isfile(SECURITY_LOG), f"Security log {SECURITY_LOG} was not created."

    with open(SECURITY_LOG, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_malicious_paths = [
        "../../.ssh/authorized_keys",
        "../config.json"
    ]

    for path in expected_malicious_paths:
        assert path in lines, f"Malicious path '{path}' was not logged in {SECURITY_LOG}."


def test_zz_execute_script_on_fresh_archive():
    token = secrets.token_hex(12)
    valid_entries = [
        (f"generated/{token}/notice.txt", b"Fresh archive: \xa9 \xff \x80 " + token.encode("ascii")),
        (f"generated/{token}/nested/caf\u00e9.txt", b"umlauts: \xe4\xf6\xfc and pound: \xa3"),
        (f"space dir/{token}.txt", b"line one\nline two\x00end"),
    ]
    malicious_entries = [
        (f"../escape_{token}.txt", b"must not escape one"),
        (f"nested/../../escape2_{token}.txt", b"must not escape two"),
        (f"/home/user/absolute_escape_{token}.txt", b"must not escape three"),
    ]

    external_paths = [
        f"/home/user/escape_{token}.txt",
        f"/home/user/escape2_{token}.txt",
        f"/home/user/absolute_escape_{token}.txt",
    ]

    shutil.rmtree(OUTBOX_DIR, ignore_errors=True)
    os.makedirs(OUTBOX_DIR, exist_ok=True)
    if os.path.lexists(SECURITY_LOG):
        os.unlink(SECURITY_LOG)
    for path in external_paths:
        if os.path.lexists(path):
            os.unlink(path)

    with open(ARCHIVE_PATH, "wb") as archive:
        for path, payload in valid_entries + malicious_entries:
            encoded_path = path.encode("utf-16-le")
            archive.write(struct.pack("<H", len(encoded_path)))
            archive.write(encoded_path)
            archive.write(struct.pack("<I", len(payload)))
            archive.write(payload)

    marker = f"/tmp/mmap-used-{uuid.uuid4().hex}"
    runner = r'''
import os
import runpy
import sys

archive = os.environ["CHECKED_ARCHIVE"]
marker = os.environ["MMAP_MARKER"]
script = os.environ["CHECKED_SCRIPT"]
state = {"mapped_archive": False}

def audit(event, args):
    if event != "mmap.__new__" or not args:
        return
    try:
        fd = int(args[0])
        if fd >= 0 and os.path.samefile(f"/proc/self/fd/{fd}", archive):
            state["mapped_archive"] = True
    except (OSError, ValueError, TypeError):
        pass

sys.addaudithook(audit)
sys.argv = [script]
try:
    runpy.run_path(script, run_name="__main__")
finally:
    with open(marker, "w", encoding="ascii") as f:
        f.write("1" if state["mapped_archive"] else "0")
'''
    env = os.environ.copy()
    env.update({
        "CHECKED_ARCHIVE": ARCHIVE_PATH,
        "CHECKED_SCRIPT": SCRIPT_PATH,
        "MMAP_MARKER": marker,
    })
    result = subprocess.run(
        [sys.executable, "-c", runner],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(marker), "The mmap runtime check did not complete."
    with open(marker, "r", encoding="ascii") as f:
        mmap_used = f.read()
    os.unlink(marker)
    assert mmap_used == "1", "The script did not memory-map the .binpack archive while executing."

    expected_files = set()
    for relative_path, payload in valid_entries:
        output_path = os.path.join(OUTBOX_DIR, relative_path)
        expected_files.add(os.path.normpath(output_path))
        assert os.path.isfile(output_path), f"Valid generated file {output_path} was not extracted."
        with open(output_path, "rb") as f:
            actual = f.read()
        expected = payload.decode("iso-8859-1").encode("utf-8")
        assert actual == expected, f"Generated file {output_path} was not converted from ISO-8859-1 to UTF-8 correctly."
        actual.decode("utf-8")

    actual_files = {
        os.path.normpath(os.path.join(root, name))
        for root, _, names in os.walk(OUTBOX_DIR)
        for name in names
    }
    assert actual_files == expected_files, "The fresh extraction produced missing or unexpected files."

    for path in external_paths:
        assert not os.path.exists(path), f"Zip-slip vulnerability triggered while executing the script: {path}"

    assert os.path.isfile(SECURITY_LOG), f"Security log {SECURITY_LOG} was not created during fresh execution."
    with open(SECURITY_LOG, "r", encoding="utf-8") as f:
        logged = [line.rstrip("\r\n") for line in f if line.rstrip("\r\n")]
    expected_logged = [path for path, _ in malicious_entries]
    assert sorted(logged) == sorted(expected_logged), "The fresh archive's malicious paths were not logged exactly as supplied."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
