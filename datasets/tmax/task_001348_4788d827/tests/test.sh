#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import json
import os
import random
import secrets
import subprocess
import sys
import tempfile
import uuid
from collections import Counter

import pytest

SCRIPT_PATH = "/home/user/sanitize.py"
CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script is not executable: {SCRIPT_PATH}"


def test_vendored_package_is_fixed_and_installed():
    code = r'''
import importlib.metadata
import cypher_validator.core as core
assert importlib.metadata.version("cypher-validator") == "1.0"
assert core.extract_patterns("MATCH (a)-[*1..3]->(b)-[]->(c)-[:R]->(d)") == ["*1..3", "", ":R"]
print(core.__file__)
'''
    result = subprocess.run(
        [sys.executable, "-c", code],
        cwd="/tmp",
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Vendored package is not fixed and installed:\n{result.stderr}"


def test_sanitizer_behavior():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    # Run on clean corpus
    result_clean = subprocess.run(["python3", SCRIPT_PATH, CLEAN_DIR], capture_output=True, text=True)
    assert result_clean.returncode == 0, f"Script failed on clean corpus:\n{result_clean.stderr}"

    clean_lines = [line.strip() for line in result_clean.stdout.strip().split("\n") if line.strip()]
    clean_results = {}
    for line in clean_lines:
        parts = line.split(":")
        if len(parts) >= 2:
            clean_results[parts[0].strip()] = parts[1].strip()

    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.cypher')]
    clean_modified = []
    for f in clean_files:
        if clean_results.get(f) != "ACCEPT":
            clean_modified.append(f)

    # Run on evil corpus
    result_evil = subprocess.run(["python3", SCRIPT_PATH, EVIL_DIR], capture_output=True, text=True)
    assert result_evil.returncode == 0, f"Script failed on evil corpus:\n{result_evil.stderr}"

    evil_lines = [line.strip() for line in result_evil.stdout.strip().split("\n") if line.strip()]
    evil_results = {}
    for line in evil_lines:
        parts = line.split(":")
        if len(parts) >= 2:
            evil_results[parts[0].strip()] = parts[1].strip()

    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.cypher')]
    evil_bypassed = []
    for f in evil_files:
        if evil_results.get(f) != "REJECT":
            evil_bypassed.append(f)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    if errors:
        pytest.fail(" | ".join(errors))


def _parse_exact_output(stdout, expected):
    lines = stdout.splitlines()
    assert len(lines) == len(expected), (
        f"Expected exactly {len(expected)} output lines, got {len(lines)}:\n{stdout}"
    )

    actual = {}
    for line in lines:
        filename, separator, verdict = line.partition(": ")
        assert separator == ": ", f"Invalid output line: {line!r}"
        assert filename not in actual, f"Duplicate output for {filename!r}"
        assert verdict in {"ACCEPT", "REJECT"}, f"Invalid verdict in line: {line!r}"
        actual[filename] = verdict

    assert actual == expected


def test_randomized_mixed_directory_and_required_package_use():
    rng = random.SystemRandom()

    with tempfile.TemporaryDirectory(prefix="cypher_inputs_") as input_dir:
        expected = {}
        contents = {}

        safe_patterns = ["", " ", ":KNOWS"]
        for _ in range(12):
            kind = rng.randrange(4)
            if kind == 0:
                pattern = f"*{rng.randint(1, 5)}"
            elif kind == 1:
                high = rng.randint(1, 5)
                pattern = f"*{rng.randint(1, high)}..{high}"
            elif kind == 2:
                pattern = f"*..{rng.randint(1, 5)}"
            else:
                pattern = rng.choice(safe_patterns)

            filename = f"item_{uuid.uuid4().hex}.cypher"
            token = secrets.token_hex(8)
            query = f"MATCH (a)-[{pattern}]->(b)-[]->(c) RETURN '{token}'\n"
            contents[filename] = query
            expected[filename] = "ACCEPT"

        for _ in range(12):
            kind = rng.randrange(6)
            if kind == 0:
                pattern = "*"
            elif kind == 1:
                pattern = "*.."
            elif kind == 2:
                pattern = f"*{rng.randint(1, 5)}.."
            elif kind == 3:
                pattern = f"*{rng.randint(1, 5)}..{rng.randint(6, 30)}"
            elif kind == 4:
                pattern = f"*..{rng.randint(6, 30)}"
            else:
                pattern = f"*{rng.randint(6, 30)}"

            filename = f"item_{uuid.uuid4().hex}.cypher"
            token = secrets.token_hex(8)
            # Include an additional safe relationship to ensure every extracted
            # relationship pattern is considered.
            query = f"MATCH (a)-[*1..5]->(b)-[{pattern}]->(c) RETURN '{token}'\n"
            contents[filename] = query
            expected[filename] = "REJECT"

        for filename, query in contents.items():
            with open(os.path.join(input_dir, filename), "w", encoding="utf-8") as handle:
                handle.write(query)

        with open(os.path.join(input_dir, "ignore.txt"), "w", encoding="utf-8") as handle:
            handle.write("MATCH (a)-[*]->(b)")

        # Use one unpredictable directory containing both classes, so the result
        # cannot be inferred from the directory path.
        result = subprocess.run([SCRIPT_PATH, input_dir], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on randomized corpus:\n{result.stderr}"
        _parse_exact_output(result.stdout, expected)

        # Run in-process with the package function instrumented, proving that the
        # sanitizer invokes cypher_validator.core.extract_patterns on each query.
        wrapper = os.path.join(input_dir, "instrument.py")
        call_log = os.path.join(input_dir, "calls.json")
        with open(wrapper, "w", encoding="utf-8") as handle:
            handle.write(r'''
import json
import runpy
import sys
import cypher_validator.core as core

script, input_dir, call_log = sys.argv[1:4]
real_extract_patterns = core.extract_patterns
calls = []

def tracked(query):
    calls.append(query)
    return real_extract_patterns(query)

core.extract_patterns = tracked
sys.argv = [script, input_dir]
try:
    runpy.run_path(script, run_name="__main__")
finally:
    with open(call_log, "w", encoding="utf-8") as out:
        json.dump(calls, out)
''')

        instrumented = subprocess.run(
            [sys.executable, wrapper, SCRIPT_PATH, input_dir, call_log],
            capture_output=True,
            text=True,
        )
        assert instrumented.returncode == 0, (
            f"Instrumented sanitizer run failed:\n{instrumented.stderr}"
        )
        assert os.path.isfile(call_log), "extract_patterns call log was not produced"
        with open(call_log, encoding="utf-8") as handle:
            calls = json.load(handle)

        normalized_calls = Counter(value.strip() for value in calls)
        for query in contents.values():
            assert normalized_calls[query.strip()] >= 1, (
                "Sanitizer did not call cypher_validator.core.extract_patterns "
                "for every .cypher file"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
