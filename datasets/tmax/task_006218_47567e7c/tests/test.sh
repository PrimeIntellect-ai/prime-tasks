#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import random
import secrets
import stat
import subprocess
import sys
import tempfile

import numpy as np

PIPELINE = "/home/user/pipeline.py"
RAW = "/home/user/raw_events.jsonl"
ARTIFACT = "/home/user/artifacts/experiment_results.json"
EXPECTED_KEYS = {
    "variant_A_successes",
    "variant_A_failures",
    "variant_B_successes",
    "variant_B_failures",
    "prob_B_better_than_A",
    "benchmark_time_seconds",
    "omp_threads",
}


def load_artifact():
    assert os.path.isfile(ARTIFACT), f"Artifact file {ARTIFACT} does not exist."
    with open(ARTIFACT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {ARTIFACT} is not valid JSON."


def test_experiment_results_artifact():
    results = load_artifact()

    # Preserve the original schema assertions.
    missing_keys = EXPECTED_KEYS - set(results.keys())
    assert not missing_keys, f"Missing keys in JSON: {missing_keys}"

    # Preserve the original conversion assertions.
    assert results["variant_A_successes"] == 1, f"Expected 1 success for A, got {results['variant_A_successes']}"
    assert results["variant_A_failures"] == 3, f"Expected 3 failures for A, got {results['variant_A_failures']}"
    assert results["variant_B_successes"] == 2, f"Expected 2 successes for B, got {results['variant_B_successes']}"
    assert results["variant_B_failures"] == 2, f"Expected 2 failures for B, got {results['variant_B_failures']}"

    # Preserve the original probability assertion.
    prob = results["prob_B_better_than_A"]
    assert isinstance(prob, (int, float)), "prob_B_better_than_A must be a float"
    assert math.isclose(prob, 0.6865, abs_tol=0.001), f"Expected prob_B_better_than_A to be ~0.6865, got {prob}"

    # Preserve the original benchmark assertion.
    bench_time = results["benchmark_time_seconds"]
    assert isinstance(bench_time, (int, float)) and bench_time > 0, "benchmark_time_seconds must be a positive float"

    # Preserve the original thread assertion.
    assert results["omp_threads"] == "4", f"Expected omp_threads to be '4', got {results['omp_threads']}"


def check_pipeline_source():
    assert os.path.exists(PIPELINE), f"Required pipeline {PIPELINE} does not exist"
    mode = os.stat(PIPELINE).st_mode
    assert stat.S_ISREG(mode), f"{PIPELINE} must be a regular Python file"
    with open(PIPELINE, "r") as f:
        source = f.read()
    assert source.strip(), f"{PIPELINE} is empty"
    tree = ast.parse(source, filename=PIPELINE)

    numpy_aliases = set()
    random_aliases = set()
    beta_aliases = set()
    seed_aliases = set()
    timeit_imported = False
    function_nodes = []

    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            function_nodes.append(node)
        elif isinstance(node, ast.Import):
            for item in node.names:
                if item.name == "numpy":
                    numpy_aliases.add(item.asname or "numpy")
                if item.name == "numpy.random":
                    random_aliases.add(item.asname or "numpy.random")
                if item.name == "timeit":
                    timeit_imported = True
        elif isinstance(node, ast.ImportFrom):
            if node.module == "numpy":
                for item in node.names:
                    if item.name == "random":
                        random_aliases.add(item.asname or item.name)
            elif node.module == "numpy.random":
                for item in node.names:
                    if item.name == "beta":
                        beta_aliases.add(item.asname or item.name)
                    elif item.name == "seed":
                        seed_aliases.add(item.asname or item.name)
            elif node.module == "timeit":
                timeit_imported = True

    def is_numpy_random_method(func, method):
        if isinstance(func, ast.Name):
            return func.id in (beta_aliases if method == "beta" else seed_aliases)
        if not isinstance(func, ast.Attribute) or func.attr != method:
            return False
        value = func.value
        if isinstance(value, ast.Name) and value.id in random_aliases:
            return True
        return (
            isinstance(value, ast.Attribute)
            and value.attr == "random"
            and isinstance(value.value, ast.Name)
            and value.value.id in numpy_aliases
        )

    beta_calls = []
    seed_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and is_numpy_random_method(node.func, "beta"):
            beta_calls.append(node)
        if isinstance(node, ast.Call) and is_numpy_random_method(node.func, "seed"):
            seed_calls.append(node)

    assert beta_calls, "pipeline must call numpy.random.beta"
    assert seed_calls, "pipeline must call numpy.random.seed"
    assert timeit_imported, "pipeline must use the timeit library"

    beta_inside_function = any(
        any(call is candidate for candidate in ast.walk(fn))
        for fn in function_nodes for call in beta_calls
    )
    assert beta_inside_function, "posterior sampling must be isolated in a function"

    has_comparison_in_function = any(
        isinstance(node, ast.Compare) and any(isinstance(op, ast.Gt) for op in node.ops)
        for fn in function_nodes for node in ast.walk(fn)
    )
    assert has_comparison_in_function, "sampling function must compare B samples strictly greater than A samples"


def make_challenge():
    # Vary the population so a hardcoded artifact cannot satisfy this run.
    a_success = 1 + secrets.randbelow(4)
    a_failure = 2 + secrets.randbelow(4)
    b_success = 1 + secrets.randbelow(4)
    b_failure = 2 + secrets.randbelow(4)
    if (a_success, a_failure, b_success, b_failure) == (1, 3, 2, 2):
        b_failure += 1

    events = []
    uid = 0
    for variant, successes, failures in (
        ("A", a_success, a_failure),
        ("B", b_success, b_failure),
    ):
        for converted in ([True] * successes + [False] * failures):
            uid += 1
            user = f"challenge_{uid}_{secrets.token_hex(3)}"
            events.append({"user_id": user, "timestamp": f"2026-01-01T00:{uid:02d}:00", "event_type": "view", "variant": variant})
            if converted:
                events.append({"user_id": user, "timestamp": f"2026-01-01T01:{uid:02d}:00", "event_type": "checkout", "variant": variant})
            else:
                events.append({"user_id": user, "timestamp": f"2026-01-01T01:{uid:02d}:00", "event_type": "click", "variant": variant})
    random.SystemRandom().shuffle(events)
    return events, (a_success, a_failure, b_success, b_failure)


def test_pipeline_execution_and_required_operations():
    check_pipeline_source()
    events, counts = make_challenge()
    a_success, a_failure, b_success, b_failure = counts

    with open(RAW, "rb") as f:
        original_raw = f.read()
    original_artifact = None
    if os.path.exists(ARTIFACT):
        with open(ARTIFACT, "rb") as f:
            original_artifact = f.read()

    with tempfile.TemporaryDirectory() as instrument_dir:
        trace_path = os.path.join(instrument_dir, "trace.json")
        sitecustomize = r'''
import atexit
import inspect
import json
import os
import timeit
import numpy as np

_events = []
_trace = os.environ.get("PIPELINE_TRACE")
_orig_beta = np.random.beta
_orig_seed = np.random.seed
_orig_timer_timeit = timeit.Timer.timeit
_orig_timer_repeat = timeit.Timer.repeat

def _size_value(args, kwargs):
    size = kwargs.get("size", args[2] if len(args) > 2 else None)
    if size is None:
        return None
    if isinstance(size, tuple):
        value = 1
        for part in size:
            value *= int(part)
        return value
    return int(size)

def beta(*args, **kwargs):
    caller = inspect.currentframe().f_back.f_code.co_name
    _events.append({"kind": "beta", "size": _size_value(args, kwargs), "caller": caller})
    return _orig_beta(*args, **kwargs)

def seed(*args, **kwargs):
    value = args[0] if args else kwargs.get("seed")
    try:
        value = int(value)
    except Exception:
        value = repr(value)
    _events.append({"kind": "seed", "value": value})
    return _orig_seed(*args, **kwargs)

def timer_timeit(self, number=timeit.default_number):
    _events.append({"kind": "timeit", "number": int(number), "repeat": 1})
    return _orig_timer_timeit(self, number=number)

def timer_repeat(self, repeat=timeit.default_repeat, number=timeit.default_number):
    _events.append({"kind": "timeit", "number": int(number), "repeat": int(repeat)})
    return _orig_timer_repeat(self, repeat=repeat, number=number)

np.random.beta = beta
np.random.seed = seed
timeit.Timer.timeit = timer_timeit
timeit.Timer.repeat = timer_repeat

@atexit.register
def _write_trace():
    if _trace:
        with open(_trace, "w") as f:
            json.dump(_events, f)
'''
        with open(os.path.join(instrument_dir, "sitecustomize.py"), "w") as f:
            f.write(sitecustomize)

        try:
            with open(RAW, "w") as f:
                for event in events:
                    f.write(json.dumps(event) + "\n")

            env = os.environ.copy()
            env["OMP_NUM_THREADS"] = "4"
            env["PIPELINE_TRACE"] = trace_path
            old_pythonpath = env.get("PYTHONPATH")
            env["PYTHONPATH"] = instrument_dir + (os.pathsep + old_pythonpath if old_pythonpath else "")
            completed = subprocess.run(
                [sys.executable, PIPELINE],
                env=env,
                cwd="/home/user",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=240,
            )
            assert completed.returncode == 0, (
                f"pipeline execution failed with code {completed.returncode}\n"
                f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
            )

            results = load_artifact()
            assert set(results) == EXPECTED_KEYS, f"Artifact schema must contain exactly {EXPECTED_KEYS}"
            assert results["variant_A_successes"] == a_success
            assert results["variant_A_failures"] == a_failure
            assert results["variant_B_successes"] == b_success
            assert results["variant_B_failures"] == b_failure
            assert results["omp_threads"] == "4"
            assert isinstance(results["benchmark_time_seconds"], (int, float))
            assert results["benchmark_time_seconds"] > 0

            np.random.seed(42)
            samples_a = np.random.beta(a_success + 1, a_failure + 1, size=1_000_000)
            samples_b = np.random.beta(b_success + 1, b_failure + 1, size=1_000_000)
            expected_probability = round(float(np.mean(samples_b > samples_a)), 4)
            assert results["prob_B_better_than_A"] == expected_probability, (
                f"Expected seeded probability {expected_probability}, got "
                f"{results['prob_B_better_than_A']}"
            )

            assert os.path.isfile(trace_path), "pipeline operation trace was not produced"
            with open(trace_path) as f:
                trace = json.load(f)
            beta_events = [event for event in trace if event.get("kind") == "beta"]
            assert len(beta_events) == 102, (
                "Expected two posterior beta draws in the main run and two draws in each "
                f"of 50 benchmark runs; observed {len(beta_events)} beta calls"
            )
            assert all(event.get("size") == 1_000_000 for event in beta_events), (
                "Every posterior draw must contain exactly 1,000,000 samples"
            )
            assert all(event.get("caller") != "<module>" for event in beta_events), (
                "Sampling must be isolated in a distinct function"
            )
            timed = [event for event in trace if event.get("kind") == "timeit"]
            assert any(event.get("number", 0) * event.get("repeat", 0) == 50 for event in timed), (
                "timeit must execute the sampling operation exactly 50 times"
            )

            seed_beta_trace = [event for event in trace if event.get("kind") in ("seed", "beta")]
            seeded_pair = False
            for index, event in enumerate(seed_beta_trace):
                if event.get("kind") == "seed" and event.get("value") == 42:
                    following = seed_beta_trace[index + 1:index + 3]
                    if len(following) == 2 and all(item.get("kind") == "beta" for item in following):
                        seeded_pair = True
                        break
            assert seeded_pair, "numpy.random.seed(42) must be set immediately before the main pair of beta draws"
        finally:
            with open(RAW, "wb") as f:
                f.write(original_raw)
            if original_artifact is None:
                if os.path.exists(ARTIFACT):
                    os.remove(ARTIFACT)
            else:
                os.makedirs(os.path.dirname(ARTIFACT), exist_ok=True)
                with open(ARTIFACT, "wb") as f:
                    f.write(original_artifact)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
