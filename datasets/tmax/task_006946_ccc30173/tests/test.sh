#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import json
import os
import random
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlparse

import pytest

FIXED_URLS = [
    "http://example.com/api?role=1&points=40",
    "http://example.com/api?role=2&points=150",
    "http://example.com/api?role=1&points=200",
]


def expected_route(url):
    params = parse_qs(urlparse(url).query)
    role = int(params["role"][0])
    points = int(params["points"][0])
    if role == 1 and points < 100:
        return "basic_user"
    if role == 2 and points > 100:
        return "premium_user"
    if role == 1 and points > 100:
        return "promoted_user"
    return "404_not_found"


def generated_cases():
    rng = random.SystemRandom()
    pairs = [(1, 40), (2, 150), (1, 200), (1, 100), (2, 100), (3, 250)]
    for _ in range(18):
        pairs.append((rng.choice([1, 2, 3, 4]), rng.randint(0, 300)))

    urls = []
    for role, points in pairs:
        query = [("role", str(role)), ("points", str(points)),
                 ("nonce", str(rng.randrange(1 << 50)))]
        rng.shuffle(query)
        urls.append("http://example.com/api?" + urlencode(query))
    return urls


def test_python3_migration_and_installation():
    """Verify that the package is installed and the CLI works in Python 3."""
    cli_path = shutil.which("legacy-router-cli")
    assert cli_path is not None, "legacy-router-cli is not installed or not in PATH."

    test_url = "http://example.com/api?role=1&points=40"
    try:
        result = subprocess.run(
            ["legacy-router-cli", test_url],
            capture_output=True,
            text=True,
            check=True
        )
        output = result.stdout.strip()
        assert output == "basic_user", f"Expected 'basic_user' for {test_url}, got '{output}'"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"legacy-router-cli execution failed: {e.stderr}")

    # The migrated source itself must be valid and importable from the editable tree.
    source_root = Path("/home/user/legacy_router").resolve()
    subprocess.run(
        [sys.executable, "-m", "py_compile", "/home/user/legacy_router/setup.py"],
        check=True,
        capture_output=True,
        text=True,
    )
    module = importlib.import_module("legacy_router")
    assert Path(module.__file__).resolve().is_relative_to(source_root), \
        "legacy_router is not imported from the required editable source tree"
    router = importlib.import_module("legacy_router.router")
    importlib.import_module("legacy_router.emulator")
    importlib.import_module("legacy_router.cli")

    # Exercise both the installed CLI and the migrated routing module on cases
    # generated at verification time, including rule boundaries and misses.
    for url in generated_cases():
        expected = expected_route(url)
        result = subprocess.run(
            [cli_path, url], capture_output=True, text=True, check=True
        )
        assert result.stdout.strip() == expected, \
            f"CLI returned {result.stdout.strip()!r} for {url}; expected {expected!r}"
        assert router.route(url) == expected, \
            f"legacy_router.router.route returned the wrong result for {url}"


def test_test_suite_script_exists():
    """Verify that the Node.js test suite script exists."""
    script_path = "/home/user/test_suite.js"
    assert os.path.isfile(script_path), f"Test suite script not found at {script_path}"


def test_node_suite_actually_executes_and_captures_cli():
    """Substitute the CLI briefly to prove the Node fixture captures its output."""
    script_path = "/home/user/test_suite.js"
    json_path = "/home/user/test_results.json"
    cli_path = shutil.which("legacy-router-cli")
    assert cli_path is not None

    markers = {url: f"verifier_marker_{index}" for index, url in enumerate(FIXED_URLS)}
    fd, call_log = tempfile.mkstemp(prefix="legacy-router-calls-", suffix=".jsonl")
    os.close(fd)
    fd, backup_path = tempfile.mkstemp(
        prefix="legacy-router-cli-backup-", dir=os.path.dirname(cli_path)
    )
    os.close(fd)
    os.unlink(backup_path)

    wrapper = """#!/usr/bin/env python3
import json
import sys
MARKERS = %r
LOG = %r
if len(sys.argv) != 2 or sys.argv[1] not in MARKERS:
    sys.exit(2)
with open(LOG, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(sys.argv[1]) + "\\n")
print(MARKERS[sys.argv[1]])
""" % (markers, call_log)

    os.replace(cli_path, backup_path)
    try:
        with open(cli_path, "w", encoding="utf-8") as handle:
            handle.write(wrapper)
        os.chmod(cli_path, 0o755)
        if os.path.exists(json_path):
            os.remove(json_path)
        result = subprocess.run(
            ["node", script_path], capture_output=True, text=True
        )
        assert result.returncode == 0, \
            f"Executing node {script_path} with the instrumented CLI failed: {result.stderr}"
        assert os.path.isfile(json_path), f"{json_path} was not generated"
        with open(json_path, "r", encoding="utf-8") as handle:
            captured = json.load(handle)
        assert captured == markers, \
            "test_suite.js did not save the actual stdout returned by the CLI"
        with open(call_log, "r", encoding="utf-8") as handle:
            calls = [json.loads(line) for line in handle if line.strip()]
        for url in FIXED_URLS:
            assert url in calls, f"test_suite.js did not execute the CLI for {url}"
    finally:
        if os.path.lexists(cli_path):
            os.unlink(cli_path)
        os.replace(backup_path, cli_path)
        if os.path.exists(call_log):
            os.unlink(call_log)


def test_test_results_json_content():
    """Verify that the test_results.json file contains the expected mapping."""
    json_path = "/home/user/test_results.json"

    script_path = "/home/user/test_suite.js"
    if os.path.exists(json_path):
        os.remove(json_path)

    try:
        subprocess.run(["node", script_path], check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Executing node {script_path} failed: {e.stderr}")

    assert os.path.isfile(json_path), f"{json_path} was not generated by the Node.js script."

    with open(json_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} does not contain valid JSON.")

    expected_results = {
        "http://example.com/api?role=1&points=40": "basic_user",
        "http://example.com/api?role=2&points=150": "premium_user",
        "http://example.com/api?role=1&points=200": "promoted_user"
    }

    assert results == expected_results, f"JSON content {results} does not match expected {expected_results}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
