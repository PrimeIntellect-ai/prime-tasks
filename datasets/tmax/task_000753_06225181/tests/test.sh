#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import os
import re
import subprocess
import tempfile
import uuid

import pytest


def test_cypher_parser_installed():
    try:
        import cypher_parser
        # Preserve the original basic parser assertion.
        ast = cypher_parser.parse("MATCH (n) RETURN n")
        assert ast is not None, "cypher_parser.parse returned None"
    except ImportError:
        pytest.fail("cypher_parser could not be imported. The vendored package was not installed correctly.")
    except Exception as e:
        pytest.fail(f"cypher_parser is installed but failed to parse a simple query: {e}")


def test_vendored_package_was_fixed_and_builds():
    package_dir = "/app/vendored/cypher-parser"
    makefile_path = os.path.join(package_dir, "Makefile")
    assert os.path.isfile(makefile_path), "Vendored package Makefile is missing"

    with open(makefile_path, "r", encoding="utf-8") as f:
        active_makefile = "\n".join(line.split("#", 1)[0] for line in f)
    assert "-std=c++11" in active_makefile, "Makefile still does not supply the required -std=c++11 flag"

    result = subprocess.run(
        ["make"], cwd=package_dir, capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, (
        "Vendored cypher-parser does not build through its Makefile:\n"
        + result.stdout + "\n" + result.stderr
    )

    probe = subprocess.run(
        [
            "python3", "-c",
            "import cypher_parser, importlib.machinery; "
            "p=cypher_parser.__file__; "
            "assert any(p.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), p; "
            "assert cypher_parser.parse('MATCH (n) RETURN n') is not None"
        ],
        cwd="/tmp",
        capture_output=True,
        text=True,
    )
    assert probe.returncode == 0, "Installed parser is not a working compiled extension:\n" + probe.stderr


def test_query_filter_script_exists():
    script_path = "/home/user/query_filter.py"
    assert os.path.isfile(script_path), f"Query filter script not found at {script_path}"


def run_filter(input_dir, output_log):
    script_path = "/home/user/query_filter.py"
    result = subprocess.run(
        ["python3", script_path, "--input-dir", input_dir, "--output-log", output_log],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Script failed on {input_dir} with error:\n{result.stderr}"


def parse_log(log_path):
    results = {}
    with open(log_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if ": " in line:
                filename, status = line.split(": ", 1)
                results[filename] = status
    return results


def test_adversarial_corpus():
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    clean_log = "/tmp/test_clean.log"
    evil_log = "/tmp/test_evil.log"

    run_filter(clean_dir, clean_log)
    run_filter(evil_dir, evil_log)

    clean_results = parse_log(clean_log)
    evil_results = parse_log(evil_log)

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.cypher')]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.cypher')]

    clean_failures = []
    for f in clean_files:
        if f not in clean_results:
            clean_failures.append(f"{f} (missing)")
        elif clean_results[f] != "ACCEPT":
            clean_failures.append(f"{f} ({clean_results[f]})")

    evil_failures = []
    for f in evil_files:
        if f not in evil_results:
            evil_failures.append(f"{f} (missing)")
        elif evil_results[f] != "REJECT":
            evil_failures.append(f"{f} ({evil_results[f]})")

    errors = []
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failures)}")

    if errors:
        pytest.fail("\n".join(errors))


def test_filter_on_mixed_randomized_corpus():
    # Clean and malicious queries deliberately share one neutral, randomized
    # directory, so classification cannot be inferred from corpus paths.
    cases = [
        ("MATCH (n:Person) RETURN n.name LIMIT 25", "ACCEPT"),
        ("MATCH (a:User)-[:KNOWS]->(b:User) WHERE a.id = 7 RETURN b", "ACCEPT"),
        ("MATCH p=(a)-[*1..4]->(b) RETURN p", "ACCEPT"),
        ("MATCH (a:User), (b:Account) WHERE a.accountId = b.id RETURN a, b", "ACCEPT"),
        ("MATCH (a) MATCH (b) WHERE a.id = b.id RETURN a, b", "ACCEPT"),
        ("MATCH (n) RETURN count(n)", "ACCEPT"),
        ("CREATE (n:Person) RETURN n", "REJECT"),
        ("MATCH (n) SET n.active = true RETURN n", "REJECT"),
        ("MATCH (n) REMOVE n.legacy RETURN n", "REJECT"),
        ("MATCH (n) DELETE n", "REJECT"),
        ("MATCH (n) DETACH DELETE n", "REJECT"),
        ("merge (n:Person {id: 1}) RETURN n", "REJECT"),
        ("DROP INDEX person_name IF EXISTS", "REJECT"),
        ("MATCH (a)-[*]->(b) RETURN a, b", "REJECT"),
        ("MATCH (a)-[*..]->(b) RETURN a, b", "REJECT"),
        ("MATCH (a), (b) RETURN a, b", "REJECT"),
        ("MATCH (a) MATCH (b) RETURN a, b", "REJECT"),
    ]

    with tempfile.TemporaryDirectory(prefix="cypher-input-") as input_dir:
        expected = {}
        for query, status in cases:
            filename = uuid.uuid4().hex + ".cypher"
            expected[filename] = status
            with open(os.path.join(input_dir, filename), "w", encoding="utf-8") as f:
                f.write(query + "\n")

        output_log = os.path.join(tempfile.gettempdir(), uuid.uuid4().hex + ".log")
        try:
            run_filter(input_dir, output_log)
            assert os.path.isfile(output_log), "Filter did not create its output log"

            actual = {}
            with open(output_log, "r", encoding="utf-8") as f:
                lines = [line.rstrip("\n") for line in f]

            assert len(lines) == len(expected), "Output must contain exactly one line per .cypher file"
            for line in lines:
                match = re.fullmatch(r"([^:\n]+): (ACCEPT|REJECT)", line)
                assert match, f"Malformed output line: {line!r}"
                filename, status = match.groups()
                assert filename not in actual, f"Duplicate output for {filename}"
                actual[filename] = status

            assert actual == expected, f"Incorrect mixed-corpus classifications: expected {expected}, got {actual}"
        finally:
            if os.path.exists(output_log):
                os.remove(output_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
