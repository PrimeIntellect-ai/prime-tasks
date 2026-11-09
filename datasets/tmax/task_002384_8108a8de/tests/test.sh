#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/process_configs.py"
INPUT_PATH = "/home/user/config_changes.log"
JSON_PATH = "/home/user/hourly_summary.json"
LOG_PATH = "/home/user/pipeline.log"


def test_process_configs_script_exists():
    """Verify that the Python script was created."""
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def test_hourly_summary_json():
    """Verify that the original hourly summary JSON is correctly generated."""
    assert os.path.exists(JSON_PATH), f"The output file {JSON_PATH} does not exist. Did you run your script?"

    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")

    expected_data = {
        "2023-10-24 14": [
            "feature_flag_x=true",
            "max_connections=500",
            "timeout=30"
        ],
        "2023-10-24 15": [
            "feature_flag_x=false",
            "max_connections=600",
            "timeout=30"
        ]
    }

    assert data == expected_data, f"The content of {JSON_PATH} does not match the expected output."


def test_pipeline_log():
    """Verify that the original pipeline log is correctly generated."""
    assert os.path.exists(LOG_PATH), f"The output file {LOG_PATH} does not exist. Did you run your script?"

    with open(LOG_PATH, "r") as f:
        log_content = f.read().strip()

    expected_log = "Processed 8 lines successfully."
    assert log_content == expected_log, f"The content of {LOG_PATH} is incorrect. Expected '{expected_log}', got '{log_content}'."


def test_script_uses_regex_and_streams_file():
    """Check the explicitly required regex and line-oriented file processing."""
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()

    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT_PATH} is not valid Python: {exc}")

    regex_imported = False
    regex_calls = False
    file_vars = set()
    streams_file = False
    bulk_reads = []

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            regex_imported |= any(alias.name == "re" for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module == "re":
            regex_imported = True

        if isinstance(node, ast.With):
            for item in node.items:
                if (isinstance(item.context_expr, ast.Call)
                        and isinstance(item.context_expr.func, ast.Name)
                        and item.context_expr.func.id == "open"
                        and isinstance(item.optional_vars, ast.Name)):
                    file_vars.add(item.optional_vars.id)

        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Call):
            if isinstance(node.value.func, ast.Name) and node.value.func.id == "open":
                for target in node.targets:
                    if isinstance(target, ast.Name):
                        file_vars.add(target.id)

        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute):
                if node.func.attr in {"compile", "match", "fullmatch", "search", "findall", "finditer"}:
                    regex_calls = True
                if node.func.attr in {"read", "readlines", "read_text", "read_bytes"}:
                    bulk_reads.append(node.func.attr)
                if node.func.attr == "readline":
                    streams_file = True
            elif isinstance(node.func, ast.Name) and node.func.id in {
                "compile", "match", "fullmatch", "search", "findall", "finditer"
            }:
                regex_calls = True

    for node in ast.walk(tree):
        if isinstance(node, (ast.For, ast.comprehension)):
            iterator = node.iter
            if isinstance(iterator, ast.Name) and iterator.id in file_vars:
                streams_file = True
            elif (isinstance(iterator, ast.Call)
                  and isinstance(iterator.func, ast.Name)
                  and iterator.func.id == "open"):
                streams_file = True

    assert regex_imported and regex_calls, "The script must use a regular expression to parse log lines."
    assert streams_file, "The script must process the input file line-by-line."
    assert not bulk_reads, f"The script uses bulk file-reading method(s), contrary to the streaming requirement: {bulk_reads}"


def test_script_on_unseen_fixture():
    """Execute the submitted artifact and derive expected output from an unseen fixture."""
    paths = [INPUT_PATH, JSON_PATH, LOG_PATH]
    backups = {}
    for path in paths:
        if os.path.exists(path):
            with open(path, "rb") as f:
                backups[path] = f.read()
        else:
            backups[path] = None

    token = secrets.token_hex(8)
    hours = ["2024-01-31 23", "2024-02-01 00", "2025-12-09 07"]
    changes = {
        hours[0]: [f"alpha={token}", "mode=safe", "zeta=9"],
        hours[1]: [f"alpha={token}", "mode=fast", "path=/tmp/a=b"],
        hours[2]: ["enabled=true", f"nonce={token[::-1]}", "workers=17"],
    }

    lines = []
    for hour_index, hour in enumerate(hours):
        for pair_index, pair in enumerate(changes[hour]):
            key, value = pair.split("=", 1)
            minute = 3 + pair_index * 11
            second = 7 + hour_index + pair_index
            lines.append(f"[{hour}:{minute:02d}:{second:02d}] USER:user{hour_index}_{pair_index} CONFIG:{key}={value}")
            # Add same-hour duplicates, which must be discarded.
            lines.append(f"[{hour}:{minute + 1:02d}:{second:02d}] USER:duplicate CONFIG:{key}={value}")

    # Add further occurrences to exercise ordering and first-occurrence deduplication.
    lines.extend([
        f"[2024-02-01 00:58:59] USER:last CONFIG:mode=fast",
        f"[2024-01-31 23:59:58] USER:last CONFIG:alpha={token}",
        "[2025-12-09 07:59:57] USER:last CONFIG:workers=17",
    ])
    random.SystemRandom().shuffle(lines)

    expected = {hour: sorted(set(pairs)) for hour, pairs in changes.items()}

    try:
        with open(INPUT_PATH, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        for path in (JSON_PATH, LOG_PATH):
            if os.path.exists(path):
                os.remove(path)

        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"The script failed on an unseen input (exit {result.returncode}). "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )
        assert os.path.isfile(JSON_PATH), "The executed script did not create hourly_summary.json."
        assert os.path.isfile(LOG_PATH), "The executed script did not create pipeline.log."

        with open(JSON_PATH, "r", encoding="utf-8") as f:
            try:
                actual = json.load(f)
            except json.JSONDecodeError as exc:
                pytest.fail(f"The dynamically generated summary is invalid JSON: {exc}")
        assert actual == expected, "The script produced an incorrect summary for an unseen input."

        with open(LOG_PATH, "r", encoding="utf-8") as f:
            actual_log = f.read().strip()
        expected_log = f"Processed {len(lines)} lines successfully."
        assert actual_log == expected_log, f"Expected {expected_log!r}, got {actual_log!r}."
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
