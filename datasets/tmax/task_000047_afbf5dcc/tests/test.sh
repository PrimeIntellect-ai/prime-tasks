#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import random
import secrets
import stat
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/ci_filter.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
LEGACY_VALIDATOR = "/app/legacy_route_validator"


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable"


def test_clean_corpus_accepted():
    result = subprocess.run([SCRIPT_PATH, CLEAN_CORPUS_DIR], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"

    output_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    expected_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]

    missing = set(expected_files) - set(output_lines)
    extra = set(output_lines) - set(expected_files)

    assert not missing, f"{len(missing)} of {len(expected_files)} clean files were incorrectly rejected. Missing files: {', '.join(missing)}"
    assert not extra, f"Script outputted unexpected paths for clean corpus: {', '.join(extra)}"


def test_evil_corpus_rejected():
    result = subprocess.run([SCRIPT_PATH, EVIL_CORPUS_DIR], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"

    output_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]

    # All files in evil corpus should be rejected (i.e. not outputted)
    all_evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    bypassed = set(output_lines).intersection(set(all_evil_files))

    assert not bypassed, f"{len(bypassed)} of {len(all_evil_files)} evil files bypassed the filter. Bypassed files: {', '.join(bypassed)}"
    assert not output_lines, f"Script outputted unexpected paths for evil corpus: {', '.join(output_lines)}"


def graph_is_dag(dependencies):
    nodes = set(dependencies)
    for values in dependencies.values():
        nodes.update(values)

    visiting = set()
    visited = set()

    def visit(node):
        if node in visiting:
            return False
        if node in visited:
            return True
        visiting.add(node)
        for dependency in dependencies.get(node, []):
            if not visit(dependency):
                return False
        visiting.remove(node)
        visited.add(node)
        return True

    return all(visit(node) for node in nodes)


def test_generated_manifests_match_full_validation_rules_without_legacy_runtime_call():
    rng = random.SystemRandom()
    nonce = secrets.token_hex(8)

    route_candidates = [
        f"/api/{nonce}/ok",
        f"/api/{nonce}/ok?user=1&role=user",
        f"/api/{nonce}/../secret",
        f"/api/{nonce}/ok?note=../safe-in-query",
        f"/api/{nonce}/ok?admin=true",
        f"/api/{nonce}/ok?x=prefix-admin=true-suffix",
        f"/api/{nonce}/ok?Admin=true",
        f"/api/{nonce}/ok?id=1&id=2",
        f"/api/{nonce}/ok?id=1&ID=2",
        f"/api/{nonce}/ok?flag&flag=2",
        f"/api/{nonce}/ok?=1&=2",
        f"/api/{nonce}/ok?admin=false",
        f"/api/{nonce}/ok?x=1&&y=2",
    ]

    route_safety = {}
    for route in route_candidates:
        oracle = subprocess.run([LEGACY_VALIDATOR, route], capture_output=True)
        assert oracle.returncode in (0, 1), f"Legacy validator returned {oracle.returncode} for {route!r}"
        route_safety[route] = oracle.returncode == 0

    cases = [
        ({"a": ["b"], "b": []}, "CREATE TABLE t (id INT);", [route_candidates[0]]),
        ({"a": [], "b": ["a"], "c": ["b"]}, "ALTER TABLE t ADD COLUMN x INT;", [route_candidates[1], route_candidates[3]]),
        ({"a": ["a"]}, "CREATE TABLE t (id INT);", [route_candidates[0]]),
        ({"a": ["b"], "b": ["c"], "c": ["a"]}, "CREATE TABLE t (id INT);", [route_candidates[0]]),
        ({"a": []}, "please DrOp TaBlE t;", [route_candidates[0]]),
        ({"a": []}, "CREATE TABLE t (id INT);", [route_candidates[2]]),
        ({"a": []}, "CREATE TABLE t (id INT);", [route_candidates[4]]),
        ({"a": []}, "CREATE TABLE t (id INT);", [route_candidates[7]]),
        ({"a": []}, "CREATE TABLE t (id INT);", [route_candidates[6], route_candidates[8], route_candidates[11]]),
    ]

    for index in range(45):
        count = rng.randint(1, 6)
        nodes = [f"n{index}_{i}_{nonce}" for i in range(count)]
        dependencies = {node: [] for node in nodes}
        for source in nodes:
            for target in nodes:
                if rng.random() < 0.20:
                    dependencies[source].append(target)
        migration = rng.choice([
            "CREATE TABLE generated (id INT);",
            "ALTER TABLE generated ADD COLUMN name TEXT;",
            "drop table generated;",
            "/* migration */ DrOp TaBlE generated;",
        ])
        routes = [rng.choice(route_candidates) for _ in range(rng.randint(1, 3))]
        cases.append((dependencies, migration, routes))

    expected = set()
    with tempfile.TemporaryDirectory(prefix=f"ci-filter-{nonce}-") as corpus_dir:
        for index, (dependencies, migration, routes) in enumerate(cases):
            filename = f"manifest_{secrets.token_hex(6)}_{index}.json"
            path = os.path.abspath(os.path.join(corpus_dir, filename))
            manifest = {
                "service_name": f"generated_{nonce}_{index}",
                "dependencies": dependencies,
                "schema_migration": migration,
                "routes": routes,
            }
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(manifest, handle)

            valid = (
                graph_is_dag(dependencies)
                and "drop table" not in migration.lower()
                and all(route_safety[route] for route in routes)
            )
            if valid:
                expected.add(path)

        assert expected, "Generated corpus unexpectedly contained no valid manifests"
        assert len(expected) < len(cases), "Generated corpus unexpectedly contained no invalid manifests"

        legacy_stat = os.stat(LEGACY_VALIDATOR)
        with open(LEGACY_VALIDATOR, "rb") as handle:
            legacy_bytes = handle.read()
        os.unlink(LEGACY_VALIDATOR)
        recreated_legacy = False
        try:
            result = subprocess.run(
                [SCRIPT_PATH, corpus_dir],
                capture_output=True,
                text=True,
                timeout=15,
            )
            recreated_legacy = os.path.exists(LEGACY_VALIDATOR)
        finally:
            if os.path.exists(LEGACY_VALIDATOR):
                os.unlink(LEGACY_VALIDATOR)
            with open(LEGACY_VALIDATOR, "wb") as handle:
                handle.write(legacy_bytes)
            os.chmod(LEGACY_VALIDATOR, stat.S_IMODE(legacy_stat.st_mode))

        assert not recreated_legacy, "Submission recreated the legacy validator instead of using a pure-Python implementation"
        assert result.returncode == 0, f"Script failed on generated corpus: {result.stderr}"
        output_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        assert len(output_lines) == len(set(output_lines)), "Script output duplicate manifest paths"
        assert set(output_lines) == expected, (
            f"Generated corpus mismatch. Missing: {sorted(expected - set(output_lines))}; "
            f"unexpected: {sorted(set(output_lines) - expected)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
