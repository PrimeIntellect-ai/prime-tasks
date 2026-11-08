#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest


def normalized_lines(content):
    return [line.strip() for line in content.strip().splitlines()]


def test_sampled_bugs_csv():
    file_path = "/home/user/sampled_bugs.csv"
    assert os.path.isfile(file_path), f"Expected output file {file_path} is missing."

    expected_content = """id,region,feedback
2,US,Found a massive bug in the UI
6,US,Another BUG encountered here
3,EU,Système failed completely
8,EU,Minor error on login screen
4,JP,エラー error ⚠
10,JP,Data bug detected
"""
    with open(file_path, "r", encoding="utf-8") as f:
        actual_content = f.read()

    assert normalized_lines(actual_content) == normalized_lines(expected_content), \
        f"Content of {file_path} does not match expected output."


def test_pipeline_log():
    file_path = "/home/user/pipeline.log"
    assert os.path.isfile(file_path), f"Expected log file {file_path} is missing."

    expected_content = """TOTAL_ROWS: 11
MATCHED_BUGS: 8
SAMPLED_RECORDS: 6
"""
    with open(file_path, "r", encoding="utf-8") as f:
        actual_content = f.read()

    assert normalized_lines(actual_content) == normalized_lines(expected_content), \
        f"Content of {file_path} does not match expected output."


def test_cpp_files_exist():
    source = Path("/home/user/process.cpp")
    executable = Path("/home/user/process")
    assert source.is_file(), "Source file /home/user/process.cpp is missing."
    assert executable.is_file(), "Compiled executable /home/user/process is missing."
    assert os.access(executable, os.X_OK), "Compiled file /home/user/process is not executable."
    assert executable.read_bytes()[:4] == b"\x7fELF", "/home/user/process is not a compiled ELF executable."


def decode_escapes(text):
    return re.sub(r"\\u([0-9a-fA-F]{4})", lambda m: chr(int(m.group(1), 16)), text)


def build_case():
    token = secrets.token_hex(8)
    base = secrets.randbelow(800000) + 100000
    region_a = "A" + token
    region_b = "B" + token
    region_c = "C" + token
    region_d = "D" + token
    rows = [
        (str(base + 1), region_a, "Routine message " + token),
        (str(base + 2), region_b, r"Found a -free  marker and 3"),
        (str(base + 3), region_b, r"Decoded 5 placeholder"),
        (str(base + 4), region_b, r"Found a  marker"),
    ]
    # Replace the placeholder rows with runtime-only values that exercise decoding
    # before matching, mixed-case matching, Unicode output, and stratification.
    rows = [
        (str(base + 1), region_a, "Routine message " + token),
        (str(base + 2), region_b, r"Found a 2 placeholder"),
        (str(base + 3), region_a, r"Operation 6 placeholder"),
        (str(base + 4), region_b, "Mixed ErRoR marker " + token),
        (str(base + 5), region_c, r"5 placeholder"),
        (str(base + 6), region_a, "No issues " + token),
        (str(base + 7), region_b, "Failure after retry " + token),
        (str(base + 8), region_a, r"A BUG with symbol 7"),
        (str(base + 9), region_c, "Everything normal " + token),
        (str(base + 10), region_a, "Third error must be excluded " + token),
        (str(base + 11), region_d, r"Decoded einal and 3"),
    ]
    # Construct exact escape sequences without placing predictable fixture output
    # in the verifier source.
    rows[1] = (rows[1][0], rows[1][1], "Found a " + "\\u0062\\u0075\\u0067" + " marker \\u00e9 " + token)
    rows[2] = (rows[2][0], rows[2][1], "Operation " + "\\u0066\\u0061\\u0069\\u006c" + " marker " + token)
    rows[4] = (rows[4][0], rows[4][1], "\\u26a0 ERROR marker " + token)
    rows[7] = (rows[7][0], rows[7][1], "A BUG with symbol \\u263a " + token)
    rows[10] = (rows[10][0], rows[10][1], "Decoded e\\u0072ror and \\u65e5 " + token)
    return rows


def expected_for(rows):
    matched = []
    for row_id, region, feedback in rows:
        decoded = decode_escapes(feedback)
        if any(keyword in decoded.lower() for keyword in ("error", "bug", "fail")):
            matched.append((row_id, region, decoded))

    region_order = []
    sampled_by_region = {}
    for row in matched:
        region = row[1]
        if region not in sampled_by_region:
            sampled_by_region[region] = []
            region_order.append(region)
        if len(sampled_by_region[region]) < 2:
            sampled_by_region[region].append(row)

    sampled = [row for region in region_order for row in sampled_by_region[region]]
    csv_lines = ["id,region,feedback"] + [",".join(row) for row in sampled]
    log_lines = [
        f"TOTAL_ROWS: {len(rows)}",
        f"MATCHED_BUGS: {len(matched)}",
        f"SAMPLED_RECORDS: {len(sampled)}",
    ]
    return csv_lines, log_lines


def exercise(executable):
    rows = build_case()
    csv_lines, log_lines = expected_for(rows)
    feedback = Path("/home/user/feedback.csv")
    sampled = Path("/home/user/sampled_bugs.csv")
    pipeline_log = Path("/home/user/pipeline.log")

    feedback.write_text(
        "id,region,feedback\n" + "\n".join(",".join(row) for row in rows) + "\n",
        encoding="utf-8",
    )
    sampled.unlink(missing_ok=True)
    pipeline_log.unlink(missing_ok=True)

    result = subprocess.run(
        [str(executable)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"{executable} failed: {result.stderr}"
    assert sampled.is_file(), f"{executable} did not create sampled_bugs.csv"
    assert pipeline_log.is_file(), f"{executable} did not create pipeline.log"
    assert normalized_lines(sampled.read_text(encoding="utf-8")) == csv_lines
    assert normalized_lines(pipeline_log.read_text(encoding="utf-8")) == log_lines


def test_program_executes_pipeline_on_changed_inputs():
    paths = [
        Path("/home/user/feedback.csv"),
        Path("/home/user/sampled_bugs.csv"),
        Path("/home/user/pipeline.log"),
    ]
    backups = {path: path.read_bytes() if path.exists() else None for path in paths}
    rebuilt = Path("/tmp/process_rebuilt_for_verification")
    try:
        exercise(Path("/home/user/process"))

        compile_result = subprocess.run(
            ["g++", "-std=c++17", "/home/user/process.cpp", "-o", str(rebuilt)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"process.cpp does not compile: {compile_result.stderr}"
        assert rebuilt.read_bytes()[:4] == b"\x7fELF"
        exercise(rebuilt)
    finally:
        rebuilt.unlink(missing_ok=True)
        for path, content in backups.items():
            if content is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
