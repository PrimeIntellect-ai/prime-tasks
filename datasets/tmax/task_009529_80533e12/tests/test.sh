#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import random
import re
import shutil
import subprocess
import tempfile

PIPELINE_DIR = "/home/user/pipeline"
OUTPUT_FILE = os.path.join(PIPELINE_DIR, "final_output.json")
REQUIREMENTS_FILE = os.path.join(PIPELINE_DIR, "requirements.txt")
PROCESSOR_FILE = os.path.join(PIPELINE_DIR, "processor.py")
AGGREGATOR_FILE = os.path.join(PIPELINE_DIR, "aggregator.py")
MAIN_FILE = os.path.join(PIPELINE_DIR, "main.py")


def recover_historical_key():
    result = subprocess.run(
        ["git", "log", "-p", "--all", "--", "config.py"],
        cwd=PIPELINE_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    keys = re.findall(r'^\+?MOCK_API_KEY\s*=\s*["\']([^"\']+)["\']', result.stdout, re.MULTILINE)
    assert keys, "No historical MOCK_API_KEY assignment was found in Git history."
    return keys[0]


def test_required_artifacts_exist():
    for path in (MAIN_FILE, PROCESSOR_FILE, AGGREGATOR_FILE, REQUIREMENTS_FILE):
        assert os.path.isfile(path), f"Required artifact {path} is missing."


def test_requirements_installable_without_removing_packages():
    with open(REQUIREMENTS_FILE, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip() and not line.lstrip().startswith("#")]

    names = set()
    for line in lines:
        match = re.match(r"([A-Za-z0-9_.-]+)", line)
        if match:
            names.add(re.sub(r"[-_.]+", "-", match.group(1)).lower())

    assert "flask" in names, "Flask was removed from requirements.txt."
    assert "werkzeug" in names, "Werkzeug was removed from requirements.txt."

    target = tempfile.mkdtemp(prefix="pipeline-deps-")
    try:
        result = subprocess.run(
            [
                "python3", "-m", "pip", "install", "--disable-pip-version-check",
                "--no-input", "--target", target, "-r", REQUIREMENTS_FILE,
            ],
            cwd=PIPELINE_DIR,
            capture_output=True,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, (
            "requirements.txt cannot be installed successfully.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        env = os.environ.copy()
        env["PYTHONPATH"] = target
        imported = subprocess.run(
            ["python3", "-S", "-c", "import flask, werkzeug"],
            cwd="/tmp",
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert imported.returncode == 0, (
            "The installed Flask and Werkzeug versions are not import-compatible.\n"
            f"stdout:\n{imported.stdout}\nstderr:\n{imported.stderr}"
        )
    finally:
        shutil.rmtree(target, ignore_errors=True)


def test_processor_on_derived_record_counts():
    counts = [0, 1]
    counts.extend(random.SystemRandom().sample(range(127, 421), 3))
    script = (
        "import json\n"
        "from processor import Processor\n"
        f"counts = {counts!r}\n"
        "results = [Processor().run(n) for n in counts]\n"
        "print(json.dumps(results))\n"
    )
    result = subprocess.run(
        ["python3", "-c", script],
        cwd=PIPELINE_DIR,
        capture_output=True,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, (
        f"processor.py could not be exercised.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    actual = json.loads(result.stdout.strip().splitlines()[-1])
    assert actual == counts, f"Processor returned {actual} for requested counts {counts}."


class WeightReplacer(ast.NodeTransformer):
    def __init__(self, values):
        self.values = values
        self.in_aggregate = False
        self.replaced = False

    def visit_FunctionDef(self, node):
        old = self.in_aggregate
        if node.name == "aggregate_weights":
            self.in_aggregate = True
        node = self.generic_visit(node)
        self.in_aggregate = old
        return node

    def visit_Assign(self, node):
        node = self.generic_visit(node)
        if self.in_aggregate and any(isinstance(t, ast.Name) and t.id == "weights" for t in node.targets):
            node.value = ast.List(elts=[ast.Constant(v) for v in self.values], ctx=ast.Load())
            self.replaced = True
        return node

    def visit_AnnAssign(self, node):
        node = self.generic_visit(node)
        if self.in_aggregate and isinstance(node.target, ast.Name) and node.target.id == "weights":
            node.value = ast.List(elts=[ast.Constant(v) for v in self.values], ctx=ast.Load())
            self.replaced = True
        return node


def test_aggregator_uses_stable_summation():
    with open(AGGREGATOR_FILE, "r", encoding="utf-8") as f:
        source = f.read()

    original = [1e16, 1.2345, -1e16, 2.3456]
    rng = random.SystemRandom()
    a = rng.randrange(1001, 9000) / 10000.0
    b = rng.randrange(1001, 9000) / 10000.0
    c = rng.randrange(1001, 9000) / 10000.0
    cases = [
        original,
        [1e16, a, -1e16, b],
        [1e16, a, b, -1e16, c],
    ]

    for values in cases:
        tree = ast.parse(source, filename=AGGREGATOR_FILE)
        replacer = WeightReplacer(values)
        tree = replacer.visit(tree)
        ast.fix_missing_locations(tree)
        assert replacer.replaced, "aggregate_weights() must retain and aggregate its weights sequence."

        namespace = {"__name__": "verified_aggregator"}
        exec(compile(tree, AGGREGATOR_FILE, "exec"), namespace)
        assert callable(namespace.get("aggregate_weights")), "aggregate_weights is missing or not callable."
        actual = namespace["aggregate_weights"]()
        expected = math.fsum(values)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
            f"Stable aggregation failed for verifier-derived weights: expected {expected}, got {actual}."
        )


def test_pipeline_runs_with_recovered_key_and_rejects_wrong_key():
    key = recover_historical_key()
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    bad_env = os.environ.copy()
    bad_env["MOCK_API_KEY"] = key + "-invalid"
    bad = subprocess.run(
        ["python3", MAIN_FILE],
        cwd=PIPELINE_DIR,
        env=bad_env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert bad.returncode != 0, "main.py accepted an invalid MOCK_API_KEY."
    assert not os.path.exists(OUTPUT_FILE), "main.py generated output despite an invalid key."

    good_env = os.environ.copy()
    good_env["MOCK_API_KEY"] = key
    good = subprocess.run(
        ["python3", MAIN_FILE],
        cwd=PIPELINE_DIR,
        env=good_env,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert good.returncode == 0, (
        "The pipeline failed when run with the key recovered from Git history.\n"
        f"stdout:\n{good.stdout}\nstderr:\n{good.stderr}"
    )


def test_final_output_exists():
    assert os.path.isfile(OUTPUT_FILE), (
        f"The file {OUTPUT_FILE} was not generated. The pipeline likely failed to run "
        "or the environment variable was not set correctly."
    )


def test_final_output_correctness():
    with open(OUTPUT_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{OUTPUT_FILE} is not a valid JSON file."

    assert "records_processed" in data, "Key 'records_processed' is missing from the JSON output."
    assert data["records_processed"] == 10000, (
        f"Expected exactly 10000 records processed, but got {data['records_processed']}. "
        "The race condition in processor.py might not be fully fixed."
    )

    assert "total_weight" in data, "Key 'total_weight' is missing from the JSON output."
    weights = [1e16, 1.2345, -1e16, 2.3456]
    expected_weight = math.fsum(weights)
    actual_weight = data["total_weight"]
    assert math.isclose(actual_weight, expected_weight, rel_tol=1e-9), (
        f"Expected total_weight to be exactly {expected_weight}, but got {actual_weight}. "
        "The precision loss in aggregator.py has not been fixed properly."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
