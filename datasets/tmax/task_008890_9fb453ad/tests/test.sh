#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

OUTPUT_FILE = "/home/user/cleaned_sampled.jsonl"
SCRIPT_FILE = "/home/user/clean_pipeline.py"
RAW_DATA_DIR = "/home/user/raw_data"


def compute_expected_data():
    raw_records = []
    raw_dir = Path(RAW_DATA_DIR)

    if not raw_dir.exists():
        return {}

    # Read all raw data
    for file_path in raw_dir.glob("*.jsonl"):
        with open(file_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    raw_records.append(json.loads(line))

    # Process records
    valid_records_by_category = {}
    for record in raw_records:
        text = record.get("text", "")
        # Lowercase
        text = text.lower()
        # Remove all characters EXCEPT alphanumeric and spaces
        text = re.sub(r'[^a-z0-9 ]', '', text)
        # Replace multiple spaces with single space and strip
        text = re.sub(r' +', ' ', text).strip()

        # Tokenize
        tokens = text.split(' ') if text else []
        token_count = len(tokens)

        # Filter
        if token_count >= 3:
            cat = record["category"]
            if cat not in valid_records_by_category:
                valid_records_by_category[cat] = []

            valid_records_by_category[cat].append({
                "id": record["id"],
                "category": cat,
                "normalized_text": text,
                "token_count": token_count
            })

    # Stratify and select
    expected_output = {}
    for cat, records in valid_records_by_category.items():
        # Sort alphabetically by id
        records.sort(key=lambda x: x["id"])
        # Select first 5
        selected = records[:5]
        for rec in selected:
            expected_output[rec["id"]] = rec

    return expected_output


def read_output_exact():
    records = {}
    nonempty_lines = 0
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            nonempty_lines += 1
            try:
                record = json.loads(line)
            except json.JSONDecodeError as e:
                pytest.fail(f"Invalid JSON on line {line_num} in {OUTPUT_FILE}: {e}")
            assert isinstance(record, dict), f"Line {line_num} is not a JSON object."
            assert set(record) == {"id", "category", "normalized_text", "token_count"}
            assert record["id"] not in records, f"Duplicate id {record['id']} in output."
            records[record["id"]] = record
    assert nonempty_lines == len(records)
    return records


def assert_parallel_api_used(source):
    try:
        tree = ast.parse(source, filename=SCRIPT_FILE)
    except SyntaxError as e:
        pytest.fail(f"{SCRIPT_FILE} is not valid Python: {e}")

    supported_import = False
    imported_symbols = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "multiprocessing" or alias.name == "concurrent.futures":
                    supported_import = True
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ""
            if module == "multiprocessing" or module.startswith("multiprocessing.") or module == "concurrent.futures":
                supported_import = True
                for alias in node.names:
                    imported_symbols[alias.asname or alias.name] = alias.name
            elif module == "concurrent":
                for alias in node.names:
                    if alias.name == "futures":
                        supported_import = True

    constructors = {"Pool", "Process", "ThreadPoolExecutor", "ProcessPoolExecutor"}
    operations = {"map", "imap", "imap_unordered", "starmap", "map_async", "apply_async", "submit", "start"}
    found_constructor = False
    found_operation = False

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name):
            called = imported_symbols.get(func.id, func.id)
            if called in constructors:
                found_constructor = True
            if called in operations:
                found_operation = True
        elif isinstance(func, ast.Attribute):
            if func.attr in constructors:
                found_constructor = True
            if func.attr in operations:
                found_operation = True

    assert supported_import, (
        "The pipeline must import multiprocessing or concurrent.futures."
    )
    assert found_constructor and found_operation, (
        "The pipeline must construct and use a multiprocessing pool/process or "
        "concurrent.futures executor for parallel work."
    )


def test_00_script_exists_uses_parallelism_and_is_executable_end_to_end():
    script = Path(SCRIPT_FILE)
    assert script.exists(), f"Expected pipeline script {SCRIPT_FILE} does not exist."
    assert not script.is_symlink(), f"{SCRIPT_FILE} must be a regular Python file, not a symlink."
    assert stat.S_ISREG(script.stat().st_mode), f"{SCRIPT_FILE} is not a regular file."

    source = script.read_text(encoding="utf-8")
    assert_parallel_api_used(source)

    raw_dir = Path(RAW_DATA_DIR)
    backup_root = Path(tempfile.mkdtemp(prefix="pipeline_raw_backup_"))
    backup_dir = backup_root / "raw_data"
    shutil.copytree(raw_dir, backup_dir)

    nonce = uuid.uuid4().hex
    probe_category = "probe_" + nonce
    probe_path = raw_dir / ("batch_probe_" + nonce + ".jsonl")

    # Change a selected existing record so a precomputed output cannot pass.
    batch0 = raw_dir / "batch_0.jsonl"
    changed_lines = []
    with batch0.open("r", encoding="utf-8") as f:
        for line in f:
            rec = json.loads(line)
            if rec.get("id") == "A02":
                rec["text"] = f"Dynamic!!! MIXED {nonce[:10]}   pipeline, text"
            changed_lines.append(json.dumps(rec))
    batch0.write_text("\n".join(changed_lines) + "\n", encoding="utf-8")

    # Add an unpredictable category with more than five records to exercise
    # normalization, sorting, and the per-category selection limit.
    with probe_path.open("w", encoding="utf-8") as f:
        for index in reversed(range(7)):
            rec = {
                "id": f"P{index:02d}_{nonce[:8]}",
                "category": probe_category,
                "text": f"Probe!!! ITEM {index}   nonce-{nonce[8:16]} works well"
            }
            f.write(json.dumps(rec) + "\n")

    try:
        if os.path.lexists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
        result = subprocess.run(
            [sys.executable, SCRIPT_FILE],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Pipeline execution failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(OUTPUT_FILE), "Executing the pipeline did not create the output file."
        expected = compute_expected_data()
        actual = read_output_exact()
        assert actual == expected, "Pipeline output did not match data derived from the modified raw inputs."
    finally:
        shutil.rmtree(raw_dir, ignore_errors=True)
        shutil.copytree(backup_dir, raw_dir)
        shutil.rmtree(backup_root, ignore_errors=True)
        if os.path.lexists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
        restored_result = subprocess.run(
            [sys.executable, SCRIPT_FILE],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert restored_result.returncode == 0, (
            "Pipeline failed when regenerating the final output from the original inputs.\n"
            f"stdout:\n{restored_result.stdout}\nstderr:\n{restored_result.stderr}"
        )


def test_output_file_exists():
    """Ensure the cleaned sampled dataset file was created."""
    assert os.path.exists(OUTPUT_FILE), f"Expected output file {OUTPUT_FILE} does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file."


def test_output_file_contents():
    """Verify the contents of the output file match the expected processed data."""
    assert os.path.exists(OUTPUT_FILE), f"Cannot verify contents, {OUTPUT_FILE} is missing."

    expected_data = compute_expected_data()
    assert expected_data, "Expected data could not be computed (raw data might be missing)."

    actual_data = {}
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as e:
                pytest.fail(f"Invalid JSON on line {line_num} in {OUTPUT_FILE}: {e}")

            assert "id" in record, f"Record on line {line_num} is missing the 'id' field."
            actual_data[record["id"]] = record

    # Check total count
    expected_count = len(expected_data)
    actual_count = len(actual_data)
    assert actual_count == expected_count, (
        f"Expected exactly {expected_count} records, but found {actual_count}."
    )

    # Check each expected record
    for expected_id, expected_record in expected_data.items():
        assert expected_id in actual_data, f"Expected record with id '{expected_id}' is missing from the output."

        actual_record = actual_data[expected_id]

        # Check exact keys
        expected_keys = {"id", "category", "normalized_text", "token_count"}
        actual_keys = set(actual_record.keys())
        assert actual_keys == expected_keys, (
            f"Record {expected_id} has incorrect keys. Expected {expected_keys}, got {actual_keys}."
        )

        # Check values
        assert actual_record["category"] == expected_record["category"], (
            f"Record {expected_id} has wrong category. Expected '{expected_record['category']}', got '{actual_record['category']}'."
        )
        assert actual_record["normalized_text"] == expected_record["normalized_text"], (
            f"Record {expected_id} has wrong normalized_text. Expected '{expected_record['normalized_text']}', got '{actual_record['normalized_text']}'."
        )
        assert actual_record["token_count"] == expected_record["token_count"], (
            f"Record {expected_id} has wrong token_count. Expected {expected_record['token_count']}, got {actual_record['token_count']}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
