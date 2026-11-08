#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import secrets
import subprocess
import tempfile

import pytest

CARGO_TOML = "/home/user/graph_filter/Cargo.toml"


def run_tool(path):
    return subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", CARGO_TOML, "--", path],
        capture_output=True,
        text=True,
        timeout=30,
    )


def test_rust_project_exists():
    cargo_toml = "/home/user/graph_filter/Cargo.toml"
    assert os.path.isfile(cargo_toml), f"Rust project not found at {cargo_toml}"


def test_adversarial_corpus():
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"
    cargo_toml = "/home/user/graph_filter/Cargo.toml"

    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failures = []
    for f in clean_files:
        result = subprocess.run(
            ["cargo", "run", "--manifest-path", cargo_toml, "--", f],
            capture_output=True
        )
        if result.returncode != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        result = subprocess.run(
            ["cargo", "run", "--manifest-path", cargo_toml, "--", f],
            capture_output=True
        )
        if result.returncode == 0:
            evil_failures.append(os.path.basename(f))

    error_msgs = []
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def extract_allowed_types():
    result = subprocess.run(
        ["tesseract", "/app/schema_rules.png", "stdout"],
        capture_output=True,
        text=True,
        timeout=30,
        check=True,
    )
    for line in result.stdout.splitlines():
        if "ALLOWED_EDGES" in line:
            tail = line.split(":", 1)[1]
            values = [value.strip() for value in tail.split(",")]
            values = [value for value in values if re.fullmatch(r"[A-Z][A-Z_]*", value)]
            if values:
                return values
    pytest.fail(f"Could not derive allowed edge types from schema image: {result.stdout!r}")


def edge(source, target, edge_type, query=None):
    properties = {}
    if query is not None:
        properties["post_hook_query"] = query
    return {
        "source": source,
        "target": target,
        "type": edge_type,
        "properties": properties,
    }


def test_generated_rule_cases_on_one_neutral_path():
    allowed = extract_allowed_types()
    assert "BACKUP_OF" in allowed, "Schema image must provide BACKUP_OF for topology checks"
    non_backup = next((value for value in allowed if value != "BACKUP_OF"), None)
    assert non_backup is not None, "Schema must provide a non-BACKUP_OF relationship"

    nonce = secrets.token_hex(8)
    unknown = "UNLISTED_" + secrets.token_hex(8).upper()
    assert unknown not in allowed

    cases = []

    # Every relationship obtained from the image is valid when used in an acyclic graph.
    all_allowed = [
        edge(f"SRC_{nonce}_{i}", f"DST_{nonce}_{i}", edge_type, "MATCH (n) RETURN n")
        for i, edge_type in enumerate(allowed)
    ]
    cases.append(("all schema relationships", all_allowed, True))
    cases.append(("empty graph", [], True))

    # Rule A: unknown, case-changed, and whitespace-padded types are not strict matches.
    cases.append(("unknown relationship", [edge("A", "B", unknown)], False))
    cases.append(("case-changed relationship", [edge("A", "B", allowed[0].lower())], False))
    cases.append(("padded relationship", [edge("A", "B", " " + allowed[0] + " ")], False))

    # Rule B: each forbidden substring is checked case-insensitively, including when embedded.
    spellings = {
        "DELETE": "deLeTe",
        "DROP": "dRoP",
        "REMOVE": "reMoVe",
        "SET": "sEt",
    }
    for keyword, spelling in spellings.items():
        query = f"MATCH (n) RETURN prefix{spelling}suffix"
        cases.append((f"injection substring {keyword}", [edge("A", "B", non_backup, query)], False))

    # Rule C: BACKUP_OF DAGs pass, while self-loops and randomized multi-node cycles fail.
    a, b, c, d = [f"NODE_{nonce}_{i}" for i in range(4)]
    cases.append((
        "backup DAG",
        [edge(a, b, "BACKUP_OF"), edge(a, c, "BACKUP_OF"), edge(b, d, "BACKUP_OF"), edge(c, d, "BACKUP_OF")],
        True,
    ))
    cases.append(("backup self-cycle", [edge(a, a, "BACKUP_OF")], False))
    cases.append((
        "backup multi-node cycle",
        [edge(a, b, "BACKUP_OF"), edge(b, c, "BACKUP_OF"), edge(c, d, "BACKUP_OF"), edge(d, a, "BACKUP_OF")],
        False,
    ))
    cases.append((
        "cycle using non-backup edges",
        [edge(a, b, non_backup), edge(b, c, non_backup), edge(c, a, non_backup)],
        True,
    ))
    cases.append((
        "mixed graph with backup cycle",
        [edge(a, b, non_backup), edge(a, c, "BACKUP_OF"), edge(c, d, "BACKUP_OF"), edge(d, a, "BACKUP_OF")],
        False,
    ))

    # Random order and one identical pathname prevent path/name or invocation-order classification.
    random.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="graph_filter_probe_") as directory:
        probe = os.path.join(directory, "input.json")
        for description, document, should_accept in cases:
            with open(probe, "w", encoding="utf-8") as handle:
                json.dump(document, handle)
            result = run_tool(probe)
            accepted = result.returncode == 0
            assert accepted == should_accept, (
                f"Incorrect result for generated case {description!r}: expected "
                f"{'acceptance' if should_accept else 'rejection'}, got exit {result.returncode}. "
                f"stderr={result.stderr!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
