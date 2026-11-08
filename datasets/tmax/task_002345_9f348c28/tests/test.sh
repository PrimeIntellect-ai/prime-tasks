#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import glob
import json
import math
import os
import random
import re
import shutil
import subprocess
import sys
import textwrap
import uuid

import pytest

PROJECT = "/home/user/project_files"
BENCHMARK = "/home/user/benchmark.py"
BENCHMARK_TXT = "/home/user/benchmark.txt"


def test_01_cycles_moved_and_results_json():
    cycles_dir = os.path.join(PROJECT, "cycles")
    assert os.path.isdir(cycles_dir), f"Directory {cycles_dir} does not exist."

    expected_cycles = {"c1.enc", "c2.enc", "c3.enc"}
    actual_cycles = set(os.listdir(cycles_dir))
    for name in expected_cycles:
        assert name in actual_cycles, f"Cyclic file {name} was not moved to {cycles_dir}."

    main_files = set(os.listdir(PROJECT))
    for name in expected_cycles:
        assert name not in main_files, f"Cyclic file {name} is still in {PROJECT}."

    results_file = os.path.join(PROJECT, "results.json")
    assert os.path.isfile(results_file), f"Results file {results_file} does not exist."
    try:
        with open(results_file, "r", encoding="utf-8") as handle:
            results = json.load(handle)
    except json.JSONDecodeError:
        pytest.fail(f"File {results_file} does not contain valid JSON.")

    expected_results = {
        "f1.enc": 30.0,
        "f2.enc": 60.0,
        "f3.enc": 30.0,
        "deep1.enc": 1.0,
        "deep2.enc": 2.0,
        "deep3.enc": 3.0,
        "deep4.enc": 4.0,
        "deep5.enc": 5.0,
    }
    for name, expected in expected_results.items():
        assert name in results, f"File {name} is missing from results.json."
        assert isinstance(results[name], (int, float)) and not isinstance(results[name], bool), \
            f"Value for {name} is not a number."
        assert abs(results[name] - expected) < 1e-6, \
            f"Incorrect value for {name}. Expected {expected}, got {results[name]}."
    for name in results:
        assert name in expected_results, f"Unexpected file {name} found in results.json."


def test_02_benchmark_is_executed_and_performs_repeated_in_memory_work(tmp_path):
    assert os.path.isfile(BENCHMARK), f"Benchmark script {BENCHMARK} does not exist."
    assert os.path.isfile(BENCHMARK_TXT), f"Benchmark output {BENCHMARK_TXT} does not exist."

    with open(BENCHMARK_TXT, "r", encoding="utf-8") as handle:
        initial = handle.read().strip()
    pattern = r"^Deepest File:\s*deep5\.enc,\s*Average Time:\s*[0-9.]+\s*us$"
    assert re.match(pattern, initial), f"Benchmark output format is incorrect. Got: '{initial}'"

    profile_path = str(tmp_path / "benchmark_profile.json")
    runner_path = str(tmp_path / "run_benchmark.py")
    runner = r'''
import collections
import json
import os
import runpy
import sys

benchmark = os.path.realpath(sys.argv[1])
outfile = sys.argv[2]
opened_enc = []
call_counts = collections.Counter()
special_counts = collections.Counter()


def audit(event, args):
    if event == "open" and args:
        try:
            path = os.path.realpath(os.fspath(args[0]))
        except (TypeError, ValueError):
            return
        if path.endswith(".enc"):
            opened_enc.append(path)


def profiler(frame, event, arg):
    if event == "call":
        filename = os.path.realpath(frame.f_code.co_filename)
        if filename.startswith("/home/user/"):
            call_counts[(filename, frame.f_code.co_name)] += 1
        if frame.f_code.co_name == "parse" and filename.endswith("/ast.py"):
            special_counts["ast.parse"] += 1
    elif event == "c_call":
        name = getattr(arg, "__name__", "")
        if name in ("eval", "compile"):
            special_counts[name] += 1
    return profiler

sys.addaudithook(audit)
sys.setprofile(profiler)
error = None
try:
    runpy.run_path(benchmark, run_name="__main__")
except SystemExit as exc:
    if exc.code not in (None, 0):
        error = "SystemExit: %r" % (exc.code,)
except BaseException as exc:
    error = "%s: %s" % (type(exc).__name__, exc)
finally:
    sys.setprofile(None)
    payload = {
        "opened_enc": opened_enc,
        "calls": {"%s::%s" % key: value for key, value in call_counts.items()},
        "special": dict(special_counts),
        "error": error,
    }
    with open(outfile, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)
if error:
    raise SystemExit(1)
'''
    with open(runner_path, "w", encoding="utf-8") as handle:
        handle.write(runner)

    os.remove(BENCHMARK_TXT)
    completed = subprocess.run(
        [sys.executable, runner_path, BENCHMARK, profile_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, \
        f"benchmark.py failed when executed:\n{completed.stdout}\n{completed.stderr}"
    assert os.path.isfile(BENCHMARK_TXT), "benchmark.py did not recreate benchmark.txt."

    with open(BENCHMARK_TXT, "r", encoding="utf-8") as handle:
        content = handle.read().strip()
    match = re.match(r"^Deepest File:\s*deep5\.enc,\s*Average Time:\s*([0-9.]+)\s*us$", content)
    assert match, f"Benchmark output format is incorrect after execution. Got: '{content}'"
    elapsed = float(match.group(1))
    assert math.isfinite(elapsed) and elapsed > 0, "Benchmark time must be a positive finite number."

    with open(profile_path, "r", encoding="utf-8") as handle:
        profile = json.load(handle)
    assert profile["error"] is None, profile["error"]

    opened_basenames = [os.path.basename(path) for path in profile["opened_enc"]]
    for name in ("deep1.enc", "deep2.enc", "deep3.enc", "deep4.enc", "deep5.enc"):
        assert name in opened_basenames, f"benchmark.py did not load dependency expression {name}."
        assert opened_basenames.count(name) <= 2, \
            f"benchmark.py repeatedly reloaded {name} instead of benchmarking in memory."

    user_call_max = max(profile["calls"].values(), default=0)
    parse_eval_count = sum(profile["special"].get(name, 0) for name in ("ast.parse", "eval", "compile"))
    with open(BENCHMARK, "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read(), filename=BENCHMARK)
    has_1000_loop = any(
        isinstance(node, (ast.For, ast.comprehension))
        and isinstance(getattr(node, "iter", None), ast.Call)
        and isinstance(node.iter.func, ast.Name)
        and node.iter.func.id == "range"
        and any(isinstance(arg, ast.Constant) and arg.value == 1000 for arg in node.iter.args)
        for node in ast.walk(tree)
    )
    assert user_call_max >= 1000 or parse_eval_count >= 1000 or has_1000_loop, \
        "benchmark.py did not perform the required 1000 repeated evaluations."


def test_03_evaluator_handles_unseen_graph_and_values():
    candidates = []
    for path in glob.glob("/home/user/**/*.py", recursive=True):
        real = os.path.realpath(path)
        if real == os.path.realpath(BENCHMARK) or "__pycache__" in real:
            continue
        if os.path.isfile(real):
            candidates.append(real)
    candidates = sorted(set(candidates))
    assert candidates, "No Python evaluation script was created."

    token = uuid.uuid4().hex[:10]
    rng = random.SystemRandom()
    a, b, c, d, e, f = [rng.randint(3, 19) for _ in range(6)]

    n1 = f"base_{token}.enc"
    n2 = f"branch_{token}.enc"
    n3 = f"chaina_{token}.enc"
    n4 = f"chainb_{token}.enc"
    lone = f"lone_{token}.enc"
    cy1 = f"loopx_{token}.enc"
    cy2 = f"loopy_{token}.enc"
    dep = f"baddep_{token}.enc"

    expressions = {
        n1: f"{a} + {b} * {c}",
        n2: f"{n1} / {d} - {e}",
        n3: f"{n2} + {n1} * 2",
        n4: f"{n3} - {n2} / 2",
        lone: f"{f} * {c} + {a}",
        cy1: f"{cy2} + 7",
        cy2: f"{cy1} / 3",
        dep: f"{cy1} * 11",
    }
    v1 = a + b * c
    v2 = v1 / d - e
    expected = {
        n1: float(v1),
        n2: float(v2),
        n3: float(v2 + v1 * 2),
        n4: float((v2 + v1 * 2) - v2 / 2),
        lone: float(f * c + a),
    }
    expected_cycles = {cy1, cy2, dep}

    def install_fixture():
        shutil.rmtree(PROJECT, ignore_errors=True)
        os.makedirs(PROJECT)
        for name, expression in expressions.items():
            encoded = base64.b64encode(expression.encode("utf-8")).decode("ascii")
            with open(os.path.join(PROJECT, name), "w", encoding="utf-8") as handle:
                handle.write(encoded)

    failures = []
    for candidate in candidates:
        install_fixture()
        try:
            completed = subprocess.run(
                [sys.executable, candidate],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
        except subprocess.TimeoutExpired:
            failures.append(f"{candidate}: timed out")
            continue
        if completed.returncode != 0:
            failures.append(f"{candidate}: exited {completed.returncode}: {completed.stderr[-300:]}")
            continue

        try:
            cycles_dir = os.path.join(PROJECT, "cycles")
            assert os.path.isdir(cycles_dir)
            assert set(os.listdir(cycles_dir)) == expected_cycles
            assert not expected_cycles.intersection(os.listdir(PROJECT))

            with open(os.path.join(PROJECT, "results.json"), "r", encoding="utf-8") as handle:
                results = json.load(handle)
            assert set(results) == set(expected)
            for name, value in expected.items():
                assert isinstance(results[name], (int, float)) and not isinstance(results[name], bool)
                assert math.isfinite(float(results[name]))
                assert abs(float(results[name]) - value) < 1e-6
        except Exception as exc:
            failures.append(f"{candidate}: incorrect randomized output ({exc})")
            continue
        return

    pytest.fail("No evaluation script correctly processed an unseen dependency graph. " + " | ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
