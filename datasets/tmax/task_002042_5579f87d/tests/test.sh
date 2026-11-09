#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path

import pytest

SCRIPT = Path("/home/user/process_data.py")
OUTPUT = Path("/home/user/clean_unique.txt")
RAW_DATA = Path("/home/user/raw_data")


def run_script():
    subprocess.run(
        [sys.executable, str(SCRIPT)],
        check=True,
        timeout=30,
        cwd="/home/user",
    )


def test_process_data_script_exists_and_executes():
    assert SCRIPT.exists(), "The required script /home/user/process_data.py is missing."
    assert not SCRIPT.is_symlink(), "/home/user/process_data.py must be a Python script, not a symbolic link."
    assert stat.S_ISREG(SCRIPT.stat().st_mode), "/home/user/process_data.py must be a regular file."

    if OUTPUT.exists():
        OUTPUT.unlink()
    run_script()
    assert OUTPUT.is_file(), "Executing process_data.py did not create /home/user/clean_unique.txt."


def test_clean_unique_file_exists():
    assert os.path.isfile("/home/user/clean_unique.txt"), "The output file /home/user/clean_unique.txt is missing."


def test_clean_unique_file_contents():
    expected_lines = [
        "16e3ba63f5cba239ed7e54f9a5d3f2ec20ebaa9dfd08269e96eab445f1b1b017:apple pie",
        "b493d48364afe44d11c0165cf470a4164d1e2609911ef998be868d46ade3de4e:banana",
        "335f60cd19aab624d62ddb03b22b4cb102eb9de3b13eb06f9e54a6db2462eaf9:café moca"
    ]

    with open("/home/user/clean_unique.txt", "r", encoding="utf-8") as f:
        content = f.read()

    assert content.endswith("\n"), "The file /home/user/clean_unique.txt must end with a newline."

    lines = content.splitlines()
    assert len(lines) == 3, f"Expected 3 lines in /home/user/clean_unique.txt, but found {len(lines)}."

    for i, expected_line in enumerate(expected_lines):
        assert lines[i] == expected_line, f"Line {i+1} does not match expected output.\nExpected: {expected_line}\nActual: {lines[i]}"


def normalize_line(line):
    value = line.strip()
    value = re.sub(r" {2,}", " ", value)
    value = value.lower()
    value = unicodedata.normalize("NFKC", value)
    return value


def test_script_processes_changed_encoded_inputs():
    payloads = [
        ("new_utf8.txt", "utf-8", "  Ｆｏｏ   BAR  \n\n"),
        ("new_latin1.txt", "iso-8859-1", "  ÉCLAIR   Test  \nDuplicate Row\n"),
        ("new_utf16.txt", "utf-16le", " foo bar \n duplicate   row \n Zebra \n"),
    ]

    expected_values = set()
    for _, _, text in payloads:
        for line in text.splitlines():
            normalized = normalize_line(line)
            if normalized:
                expected_values.add(normalized)

    expected_content = "".join(
        f"{hashlib.sha256(value.encode('utf-8')).hexdigest()}:{value}\n"
        for value in sorted(expected_values)
    )

    backup_parent = Path(tempfile.mkdtemp(prefix="raw_data_backup_"))
    backup_raw = backup_parent / "raw_data"
    shutil.copytree(RAW_DATA, backup_raw)

    try:
        shutil.rmtree(RAW_DATA)
        RAW_DATA.mkdir(parents=True)
        for filename, encoding, text in payloads:
            (RAW_DATA / filename).write_bytes(text.encode(encoding))

        if OUTPUT.exists():
            OUTPUT.unlink()
        run_script()

        assert OUTPUT.is_file(), "The script did not create output for changed input files."
        actual_content = OUTPUT.read_text(encoding="utf-8")
        assert actual_content == expected_content, (
            "process_data.py did not correctly process newly supplied encoded input files.\n"
            f"Expected:\n{expected_content}\nActual:\n{actual_content}"
        )
    finally:
        shutil.rmtree(RAW_DATA, ignore_errors=True)
        shutil.copytree(backup_raw, RAW_DATA)
        shutil.rmtree(backup_parent, ignore_errors=True)
        if SCRIPT.is_file():
            run_script()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
