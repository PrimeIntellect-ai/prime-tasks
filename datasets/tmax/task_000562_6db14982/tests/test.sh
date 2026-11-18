#!/bin/bash
set +e
mkdir -p /logs/verifier
export OMPI_ALLOW_RUN_AS_ROOT=1
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

cat <<'PY_EOF' > /tmp/execute_orchestrator.py
import json
import os
import runpy
import shlex
import subprocess
import sys

TARGET = "/home/user/run_experiment.py"
LOG = "/tmp/orchestration_trace.json"
commands = []
function_calls = []
original_popen = subprocess.Popen

def traced_popen(args, *pargs, **kwargs):
    if isinstance(args, str):
        recorded = shlex.split(args)
    else:
        recorded = [str(x) for x in args]
    commands.append(recorded)
    return original_popen(args, *pargs, **kwargs)

def profiler(frame, event, arg):
    if event == "call" and os.path.abspath(frame.f_code.co_filename) == TARGET:
        function_calls.append(frame.f_code.co_name)
    return profiler

subprocess.Popen = traced_popen
sys.setprofile(profiler)
status = 0
try:
    runpy.run_path(TARGET, run_name="__main__")
except BaseException:
    status = 1
    raise
finally:
    sys.setprofile(None)
    subprocess.Popen = original_popen
    with open(LOG, "w") as f:
        json.dump({"commands": commands, "function_calls": function_calls}, f)
PY_EOF

cat <<'PY_EOF' > /tmp/test_final_state.py
import ast
import inspect
import json
import os
import random
import secrets
import subprocess
import sys

import numpy as np
import pytest

SIMULATE = "/app/montecarlo-pi-mpi-1.0.0/simulate.py"
ORCHESTRATOR = "/home/user/run_experiment.py"
RESULTS = "/home/user/bootstrap_results.json"
TRACE = "/tmp/orchestration_trace.json"


def mpi_env():
    env = os.environ.copy()
    env["OMPI_ALLOW_RUN_AS_ROOT"] = "1"
    env["OMPI_ALLOW_RUN_AS_ROOT_CONFIRM"] = "1"
    return env


def test_simulate_script_fixed():
    path = SIMULATE
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "op=MPI.SUM" in content, f"The script {path} should have been fixed to use MPI.SUM."

    samples = 400
    seed = 9173
    completed = subprocess.run(
        ["mpirun", "-n", "4", "python", path, "--samples", str(samples), "--seed", str(seed)],
        text=True,
        capture_output=True,
        env=mpi_env(),
        timeout=60,
    )
    assert completed.returncode == 0, completed.stderr
    lines = [line for line in completed.stdout.splitlines() if "Pi Estimate:" in line]
    assert len(lines) == 1, f"Unexpected simulator output: {completed.stdout!r}"
    actual = float(lines[0].split("Pi Estimate:", 1)[1].strip())

    total_inside = 0
    for rank in range(4):
        random.seed(seed + rank * 1000)
        for _ in range(samples // 4):
            x = random.random()
            y = random.random()
            if x*x + y*y <= 1.0:
                total_inside += 1
    expected = 4.0 * total_inside / samples
    assert actual == expected, f"MPI simulation returned {actual}, expected SUM result {expected}"


def test_orchestration_executes_required_runs():
    assert os.path.isfile(ORCHESTRATOR), f"File {ORCHESTRATOR} does not exist."
    with open(ORCHESTRATOR, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=ORCHESTRATOR)
    assert any(
        isinstance(node, ast.Import) and any(alias.name == "subprocess" for alias in node.names)
        or isinstance(node, ast.ImportFrom) and node.module == "subprocess"
        for node in ast.walk(tree)
    ), "run_experiment.py must use the subprocess module."

    for path in (RESULTS, TRACE):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    completed = subprocess.run(
        [sys.executable, "/tmp/execute_orchestrator.py"],
        text=True,
        capture_output=True,
        env=mpi_env(),
        timeout=300,
    )
    assert completed.returncode == 0, (
        f"run_experiment.py failed.\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.exists(TRACE), "No subprocess execution trace was produced."
    with open(TRACE) as f:
        trace = json.load(f)

    mpi_commands = []
    for command in trace["commands"]:
        if command and os.path.basename(command[0]) in ("mpirun", "mpiexec"):
            mpi_commands.append(command)
    assert len(mpi_commands) == 50, f"Expected exactly 50 MPI subprocess executions, got {len(mpi_commands)}."

    observed_seeds = []
    for command in mpi_commands:
        assert "-n" in command and command[command.index("-n") + 1] == "4", f"Wrong MPI process count: {command}"
        assert SIMULATE in command, f"Command does not execute the required simulator: {command}"
        assert "--samples" in command and command[command.index("--samples") + 1] == "10000", f"Wrong sample count: {command}"
        assert "--seed" in command, f"Missing seed argument: {command}"
        observed_seeds.append(int(command[command.index("--seed") + 1]))
    assert sorted(observed_seeds) == list(range(50)), f"Expected seeds 0 through 49 exactly once, got {observed_seeds}"
    assert os.path.exists(RESULTS), "The executed orchestration script did not create bootstrap_results.json."


def test_bootstrap_function_is_implemented_and_used():
    with open(ORCHESTRATOR, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=ORCHESTRATOR)
    function_nodes = [node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))]
    assert function_nodes, "run_experiment.py must define a bootstrap confidence-interval function."

    # Load imports, harmless constant assignments, and function definitions without
    # rerunning the script's top-level experiment.
    selected = []
    for node in tree.body:
        if isinstance(node, (ast.Import, ast.ImportFrom, ast.FunctionDef)):
            selected.append(node)
        elif isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            try:
                ast.literal_eval(value)
            except Exception:
                continue
            selected.append(node)
    probe_tree = ast.Module(body=selected, type_ignores=[])
    ast.fix_missing_locations(probe_tree)
    namespace = {"__name__": "bootstrap_probe", "__file__": ORCHESTRATOR}
    exec(compile(probe_tree, ORCHESTRATOR, "exec"), namespace)

    rng = secrets.SystemRandom()
    observations = [rng.uniform(-7.0, 11.0) + i * 0.000137 for i in range(50)]
    np.random.seed(42)
    bootstrap_means = [
        float(np.mean(np.random.choice(np.array(observations), size=50, replace=True)))
        for _ in range(10000)
    ]
    expected_lower = float(np.percentile(bootstrap_means, 2.5))
    expected_upper = float(np.percentile(bootstrap_means, 97.5))

    matching_name = None
    errors = []
    for node in function_nodes:
        fn = namespace.get(node.name)
        if not callable(fn):
            continue
        try:
            sig = inspect.signature(fn)
            sig.bind(observations)
        except (TypeError, ValueError):
            continue
        try:
            result = fn(observations)
            if isinstance(result, dict):
                values = [float(result["ci_lower"]), float(result["ci_upper"])]
            elif isinstance(result, (tuple, list, np.ndarray)):
                values = [float(x) for x in result]
            else:
                continue
            has_lower = any(abs(x - expected_lower) <= 1e-10 for x in values)
            has_upper = any(abs(x - expected_upper) <= 1e-10 for x in values)
            if has_lower and has_upper:
                matching_name = node.name
                break
        except Exception as exc:
            errors.append(f"{node.name}: {exc}")

    assert matching_name is not None, (
        "No defined function correctly computed the NumPy seed-42, 10,000-resample, "
        f"percentile bootstrap CI on hidden observations. Errors: {errors}"
    )
    with open(TRACE) as f:
        trace = json.load(f)
    assert matching_name in trace["function_calls"], (
        f"The valid bootstrap function {matching_name!r} was not called while run_experiment.py executed."
    )


def test_bootstrap_results_metric():
    results_path = RESULTS
    assert os.path.exists(results_path), f"File {results_path} does not exist."

    with open(results_path, "r") as f:
        try:
            agent_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file bootstrap_results.json is not valid JSON.")

    assert "mean_estimate" in agent_data, "Missing 'mean_estimate' in JSON."
    assert "ci_lower" in agent_data, "Missing 'ci_lower' in JSON."
    assert "ci_upper" in agent_data, "Missing 'ci_upper' in JSON."

    agent_mean = float(agent_data["mean_estimate"])
    agent_lower = float(agent_data["ci_lower"])
    agent_upper = float(agent_data["ci_upper"])

    # Recompute ground truth.
    expected_estimates = []
    for run_index in range(50):
        total_inside = 0
        for rank in range(4):
            random.seed(run_index + rank * 1000)
            for _ in range(2500):
                x = random.random()
                y = random.random()
                if x*x + y*y <= 1.0:
                    total_inside += 1
        pi_est = 4.0 * total_inside / 10000.0
        expected_estimates.append(pi_est)

    expected_estimates = np.array(expected_estimates)
    np.random.seed(42)
    bootstrapped_means = []
    for _ in range(10000):
        sample = np.random.choice(expected_estimates, size=50, replace=True)
        bootstrapped_means.append(np.mean(sample))

    true_mean = float(np.mean(expected_estimates))
    true_lower = float(np.percentile(bootstrapped_means, 2.5))
    true_upper = float(np.percentile(bootstrapped_means, 97.5))

    max_error = max(
        abs(agent_mean - true_mean),
        abs(agent_lower - true_lower),
        abs(agent_upper - true_upper),
    )
    assert max_error <= 1e-4, (
        f"MAE {max_error} exceeds threshold 1e-4.\n"
        f"Expected: mean={true_mean}, lower={true_lower}, upper={true_upper}\n"
        f"Got: mean={agent_mean}, lower={agent_lower}, upper={agent_upper}"
    )
PY_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
