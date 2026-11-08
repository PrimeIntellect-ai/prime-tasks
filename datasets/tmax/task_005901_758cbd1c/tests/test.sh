#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import gzip
import os
import pytest

EXPECTED_LINES = [
    "id,value",
    "S1,88.5",
    "S3,91.2",
    "S5,99.9",
    "S8,85.1",
]


def normalized_lines(content):
    return [line.strip() for line in content.strip().splitlines() if line.strip()]


def test_anomalies_archive_exists_and_content_correct():
    archive_path = "/home/user/anomalies_archive.csv.gz"
    assert os.path.isfile(archive_path), f"The expected archive {archive_path} does not exist."

    try:
        with gzip.open(archive_path, "rt", encoding="utf-8") as f:
            content = f.read()
    except Exception as e:
        pytest.fail(f"Failed to read {archive_path} as a gzip file. Error: {e}")

    actual_lines = normalized_lines(content)
    assert actual_lines == EXPECTED_LINES, (
        f"The decompressed content of {archive_path} is incorrect.\n"
        f"Expected:\n{chr(10).join(EXPECTED_LINES)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_intermediate_summary_csv_exists_and_content_correct():
    summary_path = "/home/user/anomalies_summary.csv"
    assert os.path.isfile(summary_path), f"The required summary {summary_path} does not exist."

    with open(summary_path, "r", encoding="utf-8") as f:
        actual_lines = normalized_lines(f.read())

    assert actual_lines == EXPECTED_LINES, (
        f"The content of {summary_path} is incorrect.\n"
        f"Expected:\n{chr(10).join(EXPECTED_LINES)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_python_parsing_script_exists_and_is_valid_python():
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d != "__pycache__"]
        for name in files:
            if name.endswith(".py"):
                path = os.path.join(root, name)
                if os.path.isfile(path):
                    candidates.append(path)

    assert candidates, "No Python parsing script was found under /home/user."

    parse_errors = []
    for path in candidates:
        try:
            with open(path, "r", encoding="utf-8") as f:
                source = f.read()
            tree = ast.parse(source, filename=path)
            if tree.body:
                return
        except (OSError, UnicodeError, SyntaxError) as e:
            parse_errors.append(f"{path}: {e}")

    pytest.fail(
        "No non-empty, syntactically valid Python parsing script was found. "
        + "; ".join(parse_errors)
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
