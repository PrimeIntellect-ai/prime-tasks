#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import sys
import uuid

import pytest

EVIL_CORPUS_DIR = "/app/corpora/evil/"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"
VALIDATE_SCRIPT = "/home/user/validate.py"


def run_validator(path, env=None):
    return subprocess.run(
        [sys.executable, VALIDATE_SCRIPT, "--file", str(path)],
        capture_output=True,
        env=env,
        timeout=10,
    )


def test_validate_script_exists():
    assert os.path.isfile(VALIDATE_SCRIPT), f"The script {VALIDATE_SCRIPT} does not exist."


def test_vendored_package_fixed():
    config_file = "/app/gq_engine-1.0.4/gq_engine/config.py"
    assert os.path.isfile(config_file), f"File {config_file} does not exist."
    with open(config_file, "r") as f:
        content = f.read()
    assert "MAX_RECURSION_DEPTH = -1" not in content, "The perturbation in config.py was not fixed."


def test_repaired_package_is_installed_and_operational():
    code = r'''
import json
import importlib.metadata
from gq_engine import config
from gq_engine.planner import QueryPlanner
assert importlib.metadata.version("gq_engine") == "1.0.4"
assert config.MAX_RECURSION_DEPTH >= 0
plan = QueryPlanner({"max_depth": 3, "restricted_path": ["root", "child"]}).parse()
assert plan.max_depth == 3
assert plan.restricted_path == ["root", "child"]
assert plan.estimate_cost() == 600
print(json.dumps({"ok": True}))
'''
    result = subprocess.run(
        [sys.executable, "-I", "-c", code],
        cwd="/tmp",
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Installed gq_engine is not operational:\n{result.stderr}"
    assert json.loads(result.stdout.strip())["ok"] is True


def test_validator_uses_query_planner(tmp_path):
    shadow_root = tmp_path / "instrumented"
    package = shadow_root / "gq_engine"
    package.mkdir(parents=True)
    (package / "__init__.py").write_text("")
    (package / "planner.py").write_text(r'''
import os

def _mark(value):
    with open(os.environ["GQ_ENGINE_TRACE_FILE"], "a") as f:
        f.write(value + "\n")

class Plan:
    def __init__(self, max_depth, restricted_path):
        self.max_depth = max_depth
        self.restricted_path = restricted_path

    def estimate_cost(self):
        _mark("estimate_cost")
        return self.max_depth * len(self.restricted_path) * 100

class QueryPlanner:
    def __init__(self, query_dict):
        _mark("QueryPlanner")
        self.query_dict = query_dict

    def parse(self):
        _mark("parse")
        return Plan(self.query_dict.get("max_depth", 0), self.query_dict.get("restricted_path", []))
''')
    query_file = tmp_path / (uuid.uuid4().hex + ".json")
    query_file.write_text(json.dumps({"max_depth": 3, "restricted_path": ["x", "y"]}))
    trace_file = tmp_path / "planner.trace"
    env = os.environ.copy()
    env["PYTHONPATH"] = str(shadow_root)
    env["GQ_ENGINE_TRACE_FILE"] = str(trace_file)
    result = run_validator(query_file, env=env)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert trace_file.is_file(), "validate.py did not use gq_engine.planner.QueryPlanner"
    trace = trace_file.read_text().splitlines()
    assert "QueryPlanner" in trace
    assert "parse" in trace
    assert "estimate_cost" in trace


def test_generated_queries_at_unpredictable_paths(tmp_path):
    rng = random.SystemRandom()
    cases = [
        ({"max_depth": 10, "restricted_path": [uuid.uuid4().hex for _ in range(5)]}, 0),
        ({"max_depth": 10, "restricted_path": [uuid.uuid4().hex for _ in range(6)]}, 1),
        ({"max_depth": 11, "restricted_path": []}, 1),
        ({"restricted_path": [uuid.uuid4().hex, uuid.uuid4().hex]}, 0),
        ({"max_depth": 2}, 0),
    ]

    for _ in range(25):
        depth = rng.randint(0, 14)
        path = [uuid.uuid4().hex for _ in range(rng.randint(0, 8))]
        if path and rng.choice([True, False]):
            path.append(rng.choice(path))
        query = {"max_depth": depth, "restricted_path": path}
        repeated = len(path) != len(set(path))
        expected = 1 if depth * len(path) * 100 > 5000 or repeated or depth > 10 else 0
        cases.append((query, expected))

    for index, (query, expected) in enumerate(cases):
        misleading = "clean" if expected == 1 else "evil"
        directory = tmp_path / uuid.uuid4().hex
        directory.mkdir()
        query_file = directory / f"{misleading}_{index}_{uuid.uuid4().hex}.json"
        query_file.write_text(json.dumps(query))
        result = run_validator(query_file)
        assert result.returncode == expected, (
            f"Wrong result for generated query {query!r}: expected exit {expected}, "
            f"got {result.returncode}. stderr={result.stderr.decode(errors='replace')}"
        )


def test_adversarial_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory {EVIL_CORPUS_DIR} missing."
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory {CLEAN_CORPUS_DIR} missing."

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]

    assert len(evil_files) > 0, "No evil files found."
    assert len(clean_files) > 0, "No clean files found."

    evil_bypassed = []
    for evil_file in evil_files:
        result = subprocess.run(["python", VALIDATE_SCRIPT, "--file", evil_file], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    clean_modified = []
    for clean_file in clean_files:
        result = subprocess.run(["python", VALIDATE_SCRIPT, "--file", clean_file], capture_output=True)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")

    assert not errors, "Adversarial corpus validation failed:\n" + "\n".join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
