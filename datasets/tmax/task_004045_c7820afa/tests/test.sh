#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import filecmp
import io
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

EVIL_DIR = "/app/test_data/corpora/evil"
CLEAN_DIR = "/app/test_data/corpora/clean"
SCRIPT_PATH = "/home/user/sanitize_ts.py"
REFERENCE_CSV = "/app/test_data/reference.csv"


def test_fast_ts_parser_handles_embedded_newlines():
    """The installed package must parse logical CSV records, not physical lines."""
    from fast_ts_parser import parser

    marker = secrets.token_hex(8)
    data = (
        "time,value,description\r\n"
        f'1,10.0,"first {marker}\ncontinued, with comma"\r\n'
        f'2,11.0,"quoted ""{marker}"" text"\r\n'
        f'3,12.0,"last {marker}"\r\n'
    )

    parsed = parser.parse(data)

    # Support the natural documented-style representations: a DataFrame,
    # records as dictionaries, or rows as sequences (with an optional header).
    if hasattr(parsed, "to_dict") and hasattr(parsed, "columns"):
        records = parsed.to_dict(orient="records")
    else:
        try:
            rows = list(parsed)
        except TypeError as exc:
            pytest.fail(f"fast_ts_parser.parser.parse did not return iterable records: {exc}")

        assert rows, "Parser returned no CSV records"
        assert not all(isinstance(row, str) for row in rows), (
            "Parser returned strings/physical lines instead of parsed CSV fields"
        )

        if all(isinstance(row, dict) for row in rows):
            records = rows
        else:
            normalized = [list(row) for row in rows]
            if normalized and [str(v).lower() for v in normalized[0]] == [
                "time", "value", "description"
            ]:
                normalized = normalized[1:]
            records = [
                {"time": row[0], "value": row[1], "description": row[2]}
                for row in normalized
                if len(row) >= 3
            ]

    assert len(records) == 3, f"Expected 3 logical data records, got {len(records)}"
    descriptions = [str(record["description"]) for record in records]
    assert descriptions == [
        f"first {marker}\ncontinued, with comma",
        f'quoted "{marker}" text',
        f"last {marker}",
    ]
    assert [float(record["value"]) for record in records] == [10.0, 11.0, 12.0]


def test_script_imports_fast_ts_parser():
    assert os.path.isfile(SCRIPT_PATH), f"Sanitization script is missing at {SCRIPT_PATH}"
    with open(SCRIPT_PATH, "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read(), filename=SCRIPT_PATH)

    imports_package = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imports_package |= any(alias.name == "fast_ts_parser" or alias.name.startswith("fast_ts_parser.") for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imports_package |= node.module == "fast_ts_parser" or node.module.startswith("fast_ts_parser.")

    assert imports_package, "sanitize_ts.py must use the fixed fast_ts_parser library"


def test_sanitize_ts_generated_hidden_cases():
    """Exercise parsing, invalid numerics, and a cumulative DTW threshold on fresh names/data."""
    assert os.path.isfile(SCRIPT_PATH), f"Sanitization script is missing at {SCRIPT_PATH}"

    token = secrets.token_hex(10)
    names = [f"series_{token}_{i}.csv" for i in range(6)]

    reference = (
        "time,value,description\n"
        "1,10.0,reference\n"
        "2,10.0,reference\n"
        "3,10.0,reference\n"
        "4,10.0,reference\n"
    ).encode()

    # The shifted series differs by only 20 at each point, but its cumulative
    # DTW distance is greater than 50. The clean series are essentially equal.
    clean = {
        names[0]: (
            "time,value,description\n"
            f'1,10.0,"embedded {token}\nnewline"\n'
            "2,10.0,ordinary\n"
            "3,10.0,ordinary\n"
            "4,10.0,ordinary\n"
        ).encode(),
        names[1]: (
            "time,value,description\r\n"
            f'1,10.1,"comma, quote ""{token}"""\r\n'
            "2,9.9,ordinary\r\n"
            "3,10.1,ordinary\r\n"
            "4,9.9,ordinary\r\n"
        ).encode(),
    }
    rejected = {
        names[2]: (
            "time,value,description\n"
            "1,30.0,shifted\n2,30.0,shifted\n3,30.0,shifted\n4,30.0,shifted\n"
        ).encode(),
        names[3]: (
            "time,value,description\n"
            f"1,10.0,ok\n2,{token}x,invalid value\n3,10.0,ok\n4,10.0,ok\n"
        ).encode(),
        names[4]: (
            "time,value,description\n"
            f"1,10.0,ok\n{token}x,10.0,invalid time\n3,10.0,ok\n4,10.0,ok\n"
        ).encode(),
        names[5]: (
            "time,value,description\n"
            "1,-90.0,far\n2,-90.0,far\n3,-90.0,far\n4,-90.0,far\n"
        ).encode(),
    }

    with tempfile.TemporaryDirectory() as root:
        input_dir = os.path.join(root, f"input_{secrets.token_hex(5)}")
        output_dir = os.path.join(root, f"output_{secrets.token_hex(5)}")
        reference_path = os.path.join(root, f"reference_{secrets.token_hex(5)}.csv")
        os.mkdir(input_dir)
        os.mkdir(output_dir)
        with open(reference_path, "wb") as handle:
            handle.write(reference)

        for filename, content in {**clean, **rejected}.items():
            with open(os.path.join(input_dir, filename), "wb") as handle:
                handle.write(content)

        result = subprocess.run(
            [
                "python3", SCRIPT_PATH,
                "--input-dir", input_dir,
                "--output-dir", output_dir,
                "--reference", reference_path,
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Script failed with return code {result.returncode}.\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )

        assert set(os.listdir(output_dir)) == set(clean), (
            "Output must contain exactly the generated non-anomalous files"
        )
        for filename, expected in clean.items():
            output_path = os.path.join(output_dir, filename)
            assert os.path.isfile(output_path), f"Expected regular output file {filename}"
            with open(output_path, "rb") as handle:
                assert handle.read() == expected, f"Clean file {filename} was modified"


def test_sanitize_ts_adversarial_corpus():
    """
    Test the data sanitization script against the adversarial corpus.
    It must reject all evil files and preserve all clean files exactly.
    """
    assert os.path.isfile(SCRIPT_PATH), f"Sanitization script is missing at {SCRIPT_PATH}"
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory {EVIL_DIR} is missing."
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory {CLEAN_DIR} is missing."
    assert os.path.isfile(REFERENCE_CSV), f"Reference CSV {REFERENCE_CSV} is missing."

    evil_files = [f for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    clean_files = [f for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]

    assert len(evil_files) > 0, "No evil files found to test."
    assert len(clean_files) > 0, "No clean files found to test."

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        for f in evil_files:
            shutil.copy2(os.path.join(EVIL_DIR, f), os.path.join(input_dir, f))
        for f in clean_files:
            shutil.copy2(os.path.join(CLEAN_DIR, f), os.path.join(input_dir, f))

        cmd = [
            "python3", SCRIPT_PATH,
            "--input-dir", input_dir,
            "--output-dir", output_dir,
            "--reference", REFERENCE_CSV
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed with return code {result.returncode}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

        output_files = set(os.listdir(output_dir))
        evil_bypassed = [f for f in evil_files if f in output_files]
        clean_missing = [f for f in clean_files if f not in output_files]
        clean_modified = []

        for f in clean_files:
            if f in output_files:
                original_path = os.path.join(CLEAN_DIR, f)
                output_path = os.path.join(output_dir, f)
                if not filecmp.cmp(original_path, output_path, shallow=False):
                    clean_modified.append(f)

        errors = []
        if evil_bypassed:
            errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
        if clean_missing:
            errors.append(f"{len(clean_missing)} of {len(clean_files)} clean missing: {', '.join(clean_missing)}")
        if clean_modified:
            errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

        assert not errors, " | ".join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
