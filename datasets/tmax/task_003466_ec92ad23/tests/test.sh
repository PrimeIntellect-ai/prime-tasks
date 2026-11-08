#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import secrets
import subprocess
from datetime import datetime, timezone

import pytest

SCRIPT = "/home/user/process_locales.py"
OUTPUT = "/home/user/compiled_locales.jsonl"
INPUTS = [
    "/home/user/loc_servers/eu-west/updates.csv",
    "/home/user/loc_servers/us-east/updates.csv",
    "/home/user/loc_servers/ap-south/updates.csv",
]


def read_jsonl(path):
    actual_data = []
    with open(path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual_data.append(record)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {path} is not valid JSON: {line}")
    return actual_data


def test_compiled_locales_file_exists():
    """Verify that the output JSONL file has been created."""
    assert os.path.isfile(OUTPUT), f"Output file is missing: {OUTPUT}"


def test_compiled_locales_content():
    """Verify that the JSONL file contains the correctly parsed, converted, and sorted records."""
    expected_data = [
        {"timestamp": "2023-11-01T12:30:00Z", "lang_code": "es-ES", "original_text": "Settings", "translated_text": "Ajustes"},
        {"timestamp": "2023-11-01T12:30:00Z", "lang_code": "fr-FR", "original_text": "Welcome", "translated_text": "Bienvenue"},
        {"timestamp": "2023-11-01T13:00:00Z", "lang_code": "de-DE", "original_text": "Multi\nLine\nTest", "translated_text": "Mehrzeiliger\nTest\nHier"},
        {"timestamp": "2023-11-01T13:15:00Z", "lang_code": "ja-JP", "original_text": "Warning:\nLow Battery", "translated_text": "警告:\nバッテリー低下"},
        {"timestamp": "2023-11-01T15:30:00Z", "lang_code": "hi-IN", "original_text": "Submit", "translated_text": "प्रस्तुत"},
        {"timestamp": "2023-11-01T16:45:00Z", "lang_code": "es-MX", "original_text": "Error occurred", "translated_text": "Ocurrió un error\nPor favor intente de nuevo"},
    ]

    actual_data = read_jsonl(OUTPUT)
    assert len(actual_data) == len(expected_data), (
        f"Expected {len(expected_data)} records, but found {len(actual_data)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, (
            f"Record at index {i} does not match expected.\n"
            f"Actual:   {actual}\nExpected: {expected}"
        )


def dotted_name(node):
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
        return ".".join(reversed(parts))
    return None


def test_script_uses_required_csv_and_parallel_apis():
    assert os.path.isfile(SCRIPT), f"Required script is missing: {SCRIPT}"
    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT} is not valid Python: {exc}")

    module_aliases = {}
    direct_csv_readers = set()
    direct_parallel_constructors = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                bound = item.asname or item.name.split(".")[0]
                module_aliases[bound] = item.name
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ""
            for item in node.names:
                bound = item.asname or item.name
                if module == "csv" and item.name in {"reader", "DictReader"}:
                    direct_csv_readers.add(bound)
                if module in {"multiprocessing", "concurrent.futures"} and item.name in {
                    "Pool", "Process", "ProcessPoolExecutor", "ThreadPoolExecutor"
                }:
                    direct_parallel_constructors.add(bound)
                if module == "concurrent" and item.name == "futures":
                    module_aliases[bound] = "concurrent.futures"

    csv_used = False
    parallel_constructed = False
    parallel_work_scheduled = False
    scheduling_methods = {
        "map", "starmap", "imap", "imap_unordered", "map_async",
        "starmap_async", "apply_async", "submit", "start"
    }

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = dotted_name(node.func)
        if not name:
            continue
        parts = name.split(".")
        resolved = ".".join([module_aliases.get(parts[0], parts[0])] + parts[1:])

        if name in direct_csv_readers or resolved in {"csv.reader", "csv.DictReader"}:
            csv_used = True
        if name in direct_parallel_constructors or resolved in {
            "multiprocessing.Pool", "multiprocessing.Process",
            "concurrent.futures.ProcessPoolExecutor",
            "concurrent.futures.ThreadPoolExecutor",
        }:
            parallel_constructed = True
        if parts[-1] in scheduling_methods:
            parallel_work_scheduled = True

    assert csv_used, "The script must parse input with Python's csv.reader or csv.DictReader"
    assert parallel_constructed, (
        "The script must construct a multiprocessing or concurrent.futures worker pool"
    )
    assert parallel_work_scheduled, (
        "The script must schedule work through the parallel-processing API"
    )


def test_script_processes_changed_csv_inputs_when_executed():
    nonce = secrets.token_hex(8)
    rows_by_file = [
        [
            ["2026-02-03 08:10:11+05:30", "zz-ZZ", f"Comma, quote \"{nonce}\"", "First\nSecond"],
            ["2026-02-03 01:40:11-01:00", "aa-AA", "Tie record", f"alpha-{nonce}"],
            ["2024-06-01 23:59:59Z", "fr-CA", "Older", "Ligne 1\nLigne 2"],
        ],
        [
            ["2026-02-02 21:40:11-05:00", "mm-MM", "Same instant", f"middle-{nonce}"],
            ["2027-01-01 00:00:00+14:00", "ja-JP", "Future local", "引用,符号\n次"],
            ["2025-12-31 23:59:58+00:00", "es-ES", "Year edge", f"valor-{nonce}"],
        ],
        [
            ["2026-02-03 02:40:11Z", "bb-BB", "Tie again\noriginal", "Unicode Ω"],
            ["2023-01-02 03:04:05-07:00", "en-US", f"early-{nonce}", "Embedded\nnewline\nkept"],
            ["2026-02-03 03:40:11+01:00", "cc-CC", "Tie third", "শেষ"],
        ],
    ]

    input_backups = {path: open(path, "rb").read() for path in INPUTS}
    output_backup = open(OUTPUT, "rb").read() if os.path.exists(OUTPUT) else None

    try:
        for path, rows in zip(INPUTS, rows_by_file):
            with open(path, "w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                writer.writerow(["timestamp", "lang_code", "original_text", "translated_text"])
                writer.writerows(rows)

        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)

        result = subprocess.run(
            ["python3", SCRIPT],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Executing {SCRIPT} failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(OUTPUT), "The executed script did not create the required output"

        expected = []
        for path in INPUTS:
            with open(path, "r", newline="", encoding="utf-8") as f:
                for row in csv.DictReader(f):
                    parsed = datetime.fromisoformat(row["timestamp"].replace("Z", "+00:00"))
                    expected.append({
                        "timestamp": parsed.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                        "lang_code": row["lang_code"],
                        "original_text": row["original_text"],
                        "translated_text": row["translated_text"],
                    })
        expected.sort(key=lambda record: (record["timestamp"], record["lang_code"]))

        actual = read_jsonl(OUTPUT)
        assert actual == expected, (
            "Executing the script on changed CSV inputs did not produce the derived, "
            "sorted JSONL records."
        )
        assert all(set(record) == {
            "timestamp", "lang_code", "original_text", "translated_text"
        } for record in actual), "Every output object must contain exactly the required keys"
    finally:
        for path, data in input_backups.items():
            with open(path, "wb") as f:
                f.write(data)
        if output_backup is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(output_backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
