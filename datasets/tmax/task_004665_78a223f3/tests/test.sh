#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile
import pytest

AGENT_SCRIPT = "/home/user/filter.sh"
CLEAN_CORPUS_DIR = "/app/data/clean/"
EVIL_CORPUS_DIR = "/app/data/evil/"


def run_filter(path):
    try:
        return subprocess.run(
            [AGENT_SCRIPT, path],
            capture_output=True,
            timeout=3,
            env={**os.environ, "LC_ALL": "C"},
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"Could not safely execute filter on {path}: {exc}")


def test_filter_script_exists_and_executable():
    assert os.path.exists(AGENT_SCRIPT), f"The script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(AGENT_SCRIPT), f"The path {AGENT_SCRIPT} is not a file."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"The script {AGENT_SCRIPT} is not executable."
    with open(AGENT_SCRIPT, "rb") as f:
        first_line = f.readline(256).strip()
    assert first_line in (b"#!/bin/bash", b"#!/usr/bin/bash", b"#!/usr/bin/env bash"), \
        "The solution must be a Bash script with a Bash shebang."


def test_adversarial_corpus():
    if not os.path.exists(AGENT_SCRIPT) or not os.access(AGENT_SCRIPT, os.X_OK):
        pytest.fail("Agent script is missing or not executable; cannot run corpus tests.")

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    evil_bypassed = []
    clean_rejected = []

    for evil_file in evil_files:
        result = run_filter(evil_file)
        if result.returncode == 0:
            evil_bypassed.append(os.path.basename(evil_file))

    for clean_file in clean_files:
        result = run_filter(clean_file)
        if result.returncode != 0:
            clean_rejected.append(os.path.basename(clean_file))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        error_messages.append(f"{len(clean_rejected)} of {len(clean_files)} clean rejected: {', '.join(clean_rejected)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_runtime_generated_corpus():
    token = secrets.token_hex(12)
    a = "source_" + token
    b = "dest_" + secrets.token_hex(10)
    c = "node_" + secrets.token_hex(9)

    clean = [
        [],
        [{"src": a, "dst": b, "weight": 1}],
        [{"src": "", "dst": c, "weight": 0.125}],
        [
            {"src": a, "dst": b, "weight": 999999, "metadata": {"tag": token}},
            {"src": b, "dst": c, "weight": 2.75},
        ],
        [{"src": "α_" + token, "dst": "節点_" + token, "weight": 3}],
    ]

    evil = [
        {},
        None,
        "not-an-edge-list-" + token,
        [a, b],
        [{"src": a, "dst": b}],
        [{"src": a, "weight": 2}],
        [{"dst": b, "weight": 2}],
        [{"src": 7, "dst": b, "weight": 2}],
        [{"src": a, "dst": [b], "weight": 2}],
        [{"src": a + "$" + token, "dst": b, "weight": 2}],
        [{"src": a, "dst": b + "$", "weight": 2}],
        [{"src": a, "dst": b, "weight": "2"}],
        [{"src": a, "dst": b, "weight": None}],
        [{"src": a, "dst": b, "weight": 0}],
        [{"src": a, "dst": b, "weight": -0.01}],
        [{"src": a, "dst": b, "weight": [2]}],
        [{"src": a, "dst": b, "weight": {"$gt": 0}}],
        [{"src": a, "dst": b, "weight": 1}, {"src": c, "weight": 4}],
    ]

    with tempfile.TemporaryDirectory(prefix="graph-filter-" + token + "-") as td:
        cases = []
        for expected_clean, values in ((True, clean), (False, evil)):
            for value in values:
                path = os.path.join(td, secrets.token_hex(16) + ".json")
                with open(path, "w", encoding="utf-8") as f:
                    json.dump(value, f, ensure_ascii=False, separators=(",", ":"))
                cases.append((path, expected_clean))

        malformed = [
            "[",
            "not-json-" + token,
            '[{"src":"a","dst":"b","weight":1}',
            '[{"src":"a","dst":"b","weight":}]',
        ]
        for raw in malformed:
            path = os.path.join(td, secrets.token_hex(16) + ".json")
            with open(path, "w", encoding="utf-8") as f:
                f.write(raw)
            cases.append((path, False))

        failures = []
        for path, expected_clean in cases:
            result = run_filter(path)
            accepted = result.returncode == 0
            if accepted != expected_clean:
                failures.append(
                    f"{os.path.basename(path)} expected "
                    f"{'clean' if expected_clean else 'evil'}, got exit {result.returncode}"
                )
        assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
