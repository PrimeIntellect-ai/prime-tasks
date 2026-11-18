#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import json
import os
import shutil
import subprocess
import sys

import pytest

ROOT = "/home/user/telemetry"
SUMMARY = os.path.join(ROOT, "summary.json")
EXPECTED_RAW = (
    "2023-10-01T12:00:00|INFO|System started\n"
    "2023-10-01T12:05:00|WARNING|Disk space low\n"
    "2023-10-01T12:10:00|ERROR|Parsing failed on | symbol in message\n"
    "2023-10-01T12:15:00|INFO|System shutting down\n"
)
EXPECTED_RECORDS = []
for line in EXPECTED_RAW.strip().split("\n"):
    ts, lvl, msg = line.split("|", 2)
    EXPECTED_RECORDS.append({"timestamp": ts, "level": lvl, "message": msg})


def test_c_extension_built():
    """Verify a clean in-place build produces a real, importable C-extension."""
    for path in glob.glob(os.path.join(ROOT, "fast_decomp*.so")):
        os.unlink(path)
    shutil.rmtree(os.path.join(ROOT, "build"), ignore_errors=True)

    subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    so_files = glob.glob("/home/user/telemetry/fast_decomp*.so")
    assert len(so_files) > 0, "The fast_decomp C-extension was not built successfully. Make sure to run 'python3 setup.py build_ext --inplace'."
    assert any(os.path.isfile(path) for path in so_files), "The built extension is not a regular file."
    for path in so_files:
        if os.path.isfile(path):
            with open(path, "rb") as f:
                assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF shared object."

    probe = subprocess.run(
        [sys.executable, "-c", """
import importlib.machinery
import json
import os
import fast_decomp
assert isinstance(fast_decomp.__loader__, importlib.machinery.ExtensionFileLoader)
assert os.path.realpath(fast_decomp.__file__).startswith('/home/user/telemetry/')
assert callable(fast_decomp.read_all)
print(json.dumps(fast_decomp.read_all('raw_data.bin')))
"""],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert json.loads(probe.stdout.strip()) == EXPECTED_RAW, "The compiled extension did not decompress the supplied data correctly."


def test_run_pipeline():
    """Execute the required pipeline rather than trusting a pre-created JSON file."""
    if os.path.lexists(SUMMARY):
        if os.path.isdir(SUMMARY) and not os.path.islink(SUMMARY):
            shutil.rmtree(SUMMARY)
        else:
            os.unlink(SUMMARY)
    subprocess.run(
        [sys.executable, "parser.py", "raw_data.bin", "summary.json"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )


def test_summary_json_exists():
    """Verify that summary.json was generated."""
    summary_path = "/home/user/telemetry/summary.json"
    assert os.path.exists(summary_path), f"The output file {summary_path} does not exist. Did you run the parser script?"
    assert os.path.isfile(summary_path), f"{summary_path} is not a file."


def test_summary_json_content():
    """Verify every parsed field, including the embedded-pipe edge case."""
    summary_path = "/home/user/telemetry/summary.json"
    if not os.path.exists(summary_path):
        pytest.fail(f"Cannot verify contents because {summary_path} is missing.")

    try:
        with open(summary_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{summary_path} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON output should be a list of records."
    assert len(data) == 4, f"Expected exactly 4 records in the summary JSON, but found {len(data)}. Ensure no records are dropped."

    record = data[2]
    assert "level" in record, "Record is missing 'level' key."
    assert "message" in record, "Record is missing 'message' key."
    assert record["level"] == "ERROR", f"Expected the 3rd record level to be 'ERROR', got {record['level']}."
    expected_message = "Parsing failed on | symbol in message"
    assert record["message"] == expected_message, f"The 3rd record message was parsed incorrectly. Expected '{expected_message}', but got '{record['message']}'."

    assert data == EXPECTED_RECORDS, "summary.json does not exactly contain all fields from every decompressed record."


def test_parser_fixed():
    """Verify that the parser.py script was actually modified to fix the bug."""
    parser_path = "/home/user/telemetry/parser.py"
    assert os.path.exists(parser_path), "parser.py is missing."

    with open(parser_path, "r") as f:
        content = f.read()

    assert "line.split('|')" not in content or "line.split('|', 2)" in content or "line.split('|', maxsplit=2)" in content or "join" in content, "parser.py still seems to contain the buggy split logic that crashes on extra '|' characters."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
