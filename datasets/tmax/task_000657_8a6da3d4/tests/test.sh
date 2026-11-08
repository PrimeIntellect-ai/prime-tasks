#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import subprocess
import sys
import sysconfig

import pytest

APP_DIR = "/home/user/app"
INPUTS_TXT = os.path.join(APP_DIR, "inputs.txt")
RECOVERED_DB = os.path.join(APP_DIR, "recovered.db")
SUMMARY_JSON = "/home/user/summary.json"

EXPECTED_LINES = [
    "short_line_1",
    "short_line_2",
    "this_is_a_normal_length_line",
    "this_is_a_very_long_line_that_exceeds_one_hundred_characters_in_length_and_will_cause_a_segmentation_fault_when_copied_into_the_buffer_due_to_strcpy",
    "another_short_line",
]
EXPECTED_CRASHING_INPUT = EXPECTED_LINES[3]
EXPECTED_ROWS = [(i, f"event_{i}") for i in range(1, 43)]


def test_inputs_unchanged():
    """The original input file must not be modified."""
    assert os.path.isfile(INPUTS_TXT), f"Original inputs file {INPUTS_TXT} is missing."
    with open(INPUTS_TXT, "r", encoding="utf-8") as f:
        assert f.read().splitlines() == EXPECTED_LINES, "Original inputs.txt was modified."


def test_fast_parser_compiled_and_working():
    """Find an actual fast_parser extension, load it, and exercise the repaired parser."""
    extension_suffixes = tuple(
        suffix for suffix in (
            sysconfig.get_config_var("EXT_SUFFIX"),
            ".abi3.so",
            ".so",
        ) if suffix
    )
    so_files = []
    for root, dirs, files in os.walk(APP_DIR):
        for filename in files:
            if filename.startswith("fast_parser") and filename.endswith(extension_suffixes):
                so_files.append(os.path.join(root, filename))

    assert so_files, "Could not find a compiled fast_parser extension in /home/user/app/."

    test_values = EXPECTED_LINES + ["", "A" * 99, "B" * 100, "C" * 180]
    child_code = r'''
import importlib.util
import json
import os
import sys

path = os.path.realpath(sys.argv[1])
values = json.loads(sys.argv[2])
spec = importlib.util.spec_from_file_location("fast_parser", path)
if spec is None or spec.loader is None:
    raise AssertionError("Could not create an import specification for the extension")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if not callable(getattr(module, "parse", None)):
    raise AssertionError("fast_parser.parse is missing or not callable")
for value in values:
    result = module.parse(value)
    expected = len(value.encode("utf-8"))
    if type(result) is not int or result != expected:
        raise AssertionError(f"parse({value!r}) returned {result!r}, expected {expected}")
'''

    failures = []
    for path in sorted(so_files):
        try:
            result = subprocess.run(
                [sys.executable, "-c", child_code, path, json.dumps(test_values)],
                cwd=APP_DIR,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
        except subprocess.TimeoutExpired:
            failures.append(f"{path}: timed out")
            continue
        if result.returncode == 0:
            return
        failures.append(
            f"{path}: exited with {result.returncode}; stdout={result.stdout!r}; stderr={result.stderr!r}"
        )

    pytest.fail("No compiled fast_parser extension loaded and parsed safely:\n" + "\n".join(failures))


def test_recovered_db_valid():
    """Check that the recovered database is valid and contains all recovered events."""
    assert os.path.isfile(RECOVERED_DB), f"Recovered database {RECOVERED_DB} is missing."

    conn = sqlite3.connect(f"file:{RECOVERED_DB}?mode=ro", uri=True)
    cursor = conn.cursor()
    try:
        cursor.execute("PRAGMA integrity_check;")
        integrity = cursor.fetchall()
        assert integrity == [("ok",)], f"Recovered database failed integrity_check: {integrity!r}"

        cursor.execute("SELECT COUNT(*) FROM events;")
        count = cursor.fetchone()[0]
        assert isinstance(count, int), "Could not retrieve the count of records from the 'events' table."
        assert count == 42, f"Expected 42 recovered records, found {count}."

        cursor.execute("SELECT id, name FROM events ORDER BY id;")
        rows = cursor.fetchall()
        assert rows == EXPECTED_ROWS, "The recovered events table does not contain the original 42 records."
    except sqlite3.DatabaseError as e:
        pytest.fail(f"Recovered database is corrupted or invalid: {e}")
    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query the 'events' table in the recovered database: {e}")
    finally:
        conn.close()


def test_summary_json():
    """Check the summary against the unchanged inputs and independently expected recovery result."""
    assert os.path.isfile(SUMMARY_JSON), f"Summary file {SUMMARY_JSON} is missing."

    assert os.path.isfile(INPUTS_TXT), f"Original inputs file {INPUTS_TXT} is missing."
    with open(INPUTS_TXT, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    expected_crashing_input = None
    for line in lines:
        if len(line) > 100:
            expected_crashing_input = line
            break
    assert expected_crashing_input is not None, "Could not find a line longer than 100 characters in inputs.txt."
    assert expected_crashing_input == EXPECTED_CRASHING_INPUT

    assert os.path.isfile(RECOVERED_DB), f"Recovered database {RECOVERED_DB} is missing."
    conn = sqlite3.connect(f"file:{RECOVERED_DB}?mode=ro", uri=True)
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT COUNT(*) FROM events;")
        expected_recovered_records = cursor.fetchone()[0]
    except Exception as e:
        pytest.fail(f"Could not read records from recovered database to verify summary: {e}")
    finally:
        conn.close()

    assert expected_recovered_records == 42, "Recovered database must contain all 42 records."

    with open(SUMMARY_JSON, "r", encoding="utf-8") as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Summary file {SUMMARY_JSON} is not valid JSON: {e}")

    assert "crashing_input" in summary, "Summary JSON is missing the 'crashing_input' key."
    assert "recovered_records" in summary, "Summary JSON is missing the 'recovered_records' key."
    assert summary["crashing_input"] == expected_crashing_input, \
        f"Incorrect crashing_input in summary. Expected '{expected_crashing_input}', got '{summary['crashing_input']}'."
    assert summary["recovered_records"] == expected_recovered_records, \
        f"Incorrect recovered_records in summary. Expected {expected_recovered_records}, got {summary['recovered_records']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
