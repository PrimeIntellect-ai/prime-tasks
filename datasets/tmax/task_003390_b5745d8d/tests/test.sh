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

import pytest


def test_query_builder_installed():
    """Verify that the query-builder package is fixed and installed."""
    pyproject_path = "/app/vendored/query-builder-1.0.0/pyproject.toml"
    assert os.path.isfile(pyproject_path), f"File {pyproject_path} is missing"

    with open(pyproject_path, "r") as f:
        content = f.read()

    assert "fake-build-backend" not in content, "The deliberate error 'fake-build-backend' was not removed from pyproject.toml"

    try:
        import query_builder
    except ImportError:
        pytest.fail("The query_builder package is not installed or importable. Ensure you installed it after fixing pyproject.toml.")

    try:
        dist = importlib.metadata.distribution("query-builder")
    except importlib.metadata.PackageNotFoundError:
        pytest.fail("No installed query-builder distribution metadata was found")

    assert dist.version == "1.0.0", f"Expected installed query-builder version 1.0.0, got {dist.version}"
    assert callable(getattr(query_builder, "build_query", None)), "Installed query_builder does not provide build_query"
    assert query_builder.build_query({"table": "audit_events"}) == "SELECT * FROM audit_events"

    # Confirm importability in a clean interpreter, rather than through the vendored
    # source directory being added to this verifier's import path.
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    probe = subprocess.run(
        [sys.executable, "-c",
         "import importlib.metadata as m; import query_builder; "
         "assert m.version('query-builder') == '1.0.0'; "
         "assert query_builder.build_query({'table':'probe_table'}) == 'SELECT * FROM probe_table'"],
        cwd="/tmp",
        env=env,
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert probe.returncode == 0, f"Installed package failed clean import probe: {probe.stderr}"


def run_sanitizer(script, path, expected_word, expected_code):
    result = subprocess.run(
        [sys.executable, script, path],
        cwd="/tmp",
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == expected_code, (
        f"For an opaque test input, expected exit {expected_code}, got {result.returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected_word, (
        f"For an opaque test input, expected {expected_word!r}, got {result.stdout!r}"
    )


def test_sanitizer_adversarial_corpus():
    """Verify the sanitizer correctly classifies clean and evil corpora."""
    sanitizer_script = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_script), f"Sanitizer script {sanitizer_script} is missing"

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".json")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".json")]

    assert len(clean_files) > 0, "Clean corpus is empty"
    assert len(evil_files) > 0, "Evil corpus is empty"

    clean_failed = []
    for fpath in clean_files:
        result = subprocess.run([sys.executable, sanitizer_script, fpath], capture_output=True, text=True)
        stdout = result.stdout.strip()
        if result.returncode != 0 or stdout != "SAFE":
            clean_failed.append(os.path.basename(fpath))

    evil_failed = []
    for fpath in evil_files:
        result = subprocess.run([sys.executable, sanitizer_script, fpath], capture_output=True, text=True)
        stdout = result.stdout.strip()
        if result.returncode != 1 or stdout != "UNSAFE":
            evil_failed.append(os.path.basename(fpath))

    error_msgs = []
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")

    if error_msgs:
        pytest.fail("Adversarial corpus verification failed:\n" + "\n".join(error_msgs))


def test_sanitizer_on_opaque_generated_inputs():
    """Exercise content-derived cases at paths that do not disclose their labels."""
    sanitizer_script = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_script), f"Sanitizer script {sanitizer_script} is missing"

    def ident(prefix):
        return prefix + "_" + secrets.token_hex(8)

    table = ident("events")
    col1 = ident("account")
    col2 = ident("amount")
    alias = ident("metric")

    cases = [
        ({"table": table, "columns": [col1, col2]}, "SAFE", 0),
        ({"table": table, "columns": [col1, col2], "alias": alias}, "SAFE", 0),
        ({"table": table, "columns": [col1, col2],
          "window": f"ROW_NUMBER() OVER (PARTITION BY {col1})"}, "SAFE", 0),
        ({"table": table + "; DROP TABLE " + ident("archive") + "; --",
          "columns": [col1]}, "UNSAFE", 1),
        ({"table": table,
          "columns": [col1, col2 + " UNION SELECT " + ident("secret") + " FROM " + ident("admin")]},
         "UNSAFE", 1),
        ({"table": table, "columns": [col1], "alias": alias + "--comment"}, "UNSAFE", 1),
        ({"table": table, "columns": [col1 + "; DELETE FROM " + ident("ledger")]}, "UNSAFE", 1),
        ({"table": table, "columns": ["DROP TABLE " + ident("records")]}, "UNSAFE", 1),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="sanitizer_inputs_") as temp_dir:
        materialized = []
        for document, expected_word, expected_code in cases:
            path = os.path.join(temp_dir, secrets.token_hex(12) + ".json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(document, f)
            materialized.append((path, expected_word, expected_code))

        random.SystemRandom().shuffle(materialized)
        for path, expected_word, expected_code in materialized:
            run_sanitizer(sanitizer_script, path, expected_word, expected_code)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
