#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import importlib.metadata
import inspect
import json
import math
import os
import re
import shutil
import subprocess

import networkx as nx
import numpy as np
from scipy.optimize import curve_fit

INTEGRATOR = "/app/mol_sim/mol_sim/integrator.py"
CSV_PATH = "/home/user/sim_output.csv"
JSON_PATH = "/home/user/analysis.json"
RUN_SIM = "/home/user/run_sim.py"


def exp_model(t, A, k):
    return A * np.exp(-k * t)


def adaptive_rk_fixed(func, t_span, y0, tol=1e-6):
    t0, tf = t_span
    t = t0
    y = np.array(y0, dtype=float)
    ts = [t]
    ys = [y.copy()]
    dt = 0.01

    while t < tf:
        if t + dt > tf:
            dt = tf - t

        k1 = dt * func(t, y)
        k2 = dt * func(t + dt / 2, y + k1 / 2)
        k3 = dt * func(t + dt / 2, y + k2 / 2)
        k4 = dt * func(t + dt, y + k3)
        y_next = y + (k1 + 2 * k2 + 2 * k3 + k4) / 6
        err = np.max(np.abs(k2 - k3)) + 1e-12
        dt_new = dt * min(2.0, max(0.1, (tol / err) ** 0.2))

        if err <= tol:
            t += dt
            y = y_next
            ts.append(t)
            ys.append(y.copy())
        dt = dt_new

    return np.array(ts), np.array(ys)


def expected_simulation():
    np.random.seed(42)
    graph = nx.erdos_renyi_graph(10, 0.3, seed=42)
    laplacian = nx.laplacian_matrix(graph).toarray()

    def diffusion(t, y):
        return -0.5 * laplacian.dot(y)

    y0 = np.zeros(10)
    y0[0] = 10.0
    return adaptive_rk_fixed(diffusion, (0, 5.0), y0)


def assert_integrator_source_fixed():
    assert os.path.isfile(INTEGRATOR), f"Missing integrator source: {INTEGRATOR}"
    with open(INTEGRATOR, "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read(), filename=INTEGRATOR)

    adaptive = next(
        (node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
         and node.name == "adaptive_rk"),
        None,
    )
    assert adaptive is not None, "integrator.py does not define adaptive_rk"

    correct_power = False
    for node in ast.walk(adaptive):
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Pow):
            try:
                exponent = ast.literal_eval(node.right)
            except Exception:
                continue
            if isinstance(exponent, (int, float)) and not isinstance(exponent, bool):
                if math.isclose(float(exponent), 0.2, rel_tol=0, abs_tol=1e-12):
                    correct_power = True
                    break
    assert correct_power, "adaptive_rk does not use the required 0.2 step-size exponent"


def assert_package_installed():
    version = importlib.metadata.version("mol_sim")
    assert version, "mol_sim distribution is not installed"
    import mol_sim.integrator as installed
    installed_path = os.path.realpath(inspect.getfile(installed))
    assert os.path.isfile(installed_path), "Installed mol_sim.integrator is missing"


def load_csv():
    assert os.path.isfile(CSV_PATH), f"Missing simulation output: {CSV_PATH}"
    with open(CSV_PATH, "r", newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle)
        rows = list(reader)
    expected_header = ["time"] + [f"node_{i}" for i in range(10)]
    assert rows and rows[0] == expected_header, "Simulation CSV has an incorrect header"
    assert len(rows) > 1, "Simulation CSV contains no data"
    try:
        values = np.asarray([[float(value) for value in row] for row in rows[1:]], dtype=float)
    except Exception as exc:
        raise AssertionError(f"Simulation CSV contains non-numeric data: {exc}")
    assert values.ndim == 2 and values.shape[1] == 11, "Simulation CSV has an incorrect shape"
    assert np.all(np.isfinite(values)), "Simulation CSV contains NaN or infinity"
    return values


def constant_value(node, env):
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)) and not isinstance(node.value, bool):
        return node.value
    if isinstance(node, ast.Name):
        return env.get(node.id)
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
        value = constant_value(node.operand, env)
        if value is not None:
            return value if isinstance(node.op, ast.UAdd) else -value
    if isinstance(node, ast.BinOp):
        left = constant_value(node.left, env)
        right = constant_value(node.right, env)
        if left is None or right is None:
            return None
        try:
            if isinstance(node.op, ast.Add): return left + right
            if isinstance(node.op, ast.Sub): return left - right
            if isinstance(node.op, ast.Mult): return left * right
            if isinstance(node.op, ast.Div): return left / right
            if isinstance(node.op, ast.FloorDiv): return left // right
            if isinstance(node.op, ast.Pow): return left ** right
        except Exception:
            return None
    return None


def call_name(node):
    if isinstance(node, ast.Name):
        return node.id.lower()
    if isinstance(node, ast.Attribute):
        return node.attr.lower()
    return ""


def python_has_500_bootstraps(source):
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return False

    env = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value_node = node.value
            value = constant_value(value_node, env)
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if value is not None:
                for target in targets:
                    if isinstance(target, ast.Name):
                        env[target.id] = value

    resample_names = {"choice", "randint", "integers", "resample", "sample"}

    def has_resampling(subtree):
        return any(isinstance(item, ast.Call) and call_name(item.func) in resample_names
                   for item in ast.walk(subtree))

    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and call_name(node.func) == "bootstrap":
            n_arg = next((kw.value for kw in node.keywords if kw.arg == "n_resamples"), None)
            if n_arg is None or (constant_value(n_arg, env) or 0) >= 500:
                return True

        if isinstance(node, (ast.For, ast.comprehension)):
            iterator = node.iter
            if isinstance(iterator, ast.Call) and call_name(iterator.func) == "range" and iterator.args:
                count = constant_value(iterator.args[-1], env)
                if count is not None and count >= 500 and has_resampling(node):
                    return True

        if isinstance(node, ast.Call) and call_name(node.func) in resample_names:
            size_nodes = [kw.value for kw in node.keywords if kw.arg in ("size", "n_samples")]
            for size_node in size_nodes:
                values = []
                if isinstance(size_node, (ast.Tuple, ast.List)):
                    values = [constant_value(item, env) for item in size_node.elts]
                else:
                    values = [constant_value(size_node, env)]
                if any(value is not None and value >= 500 for value in values):
                    return True
    return False


def has_bootstrap_evidence(path, source):
    if path.lower().endswith(".py"):
        return python_has_500_bootstraps(source)
    lowered = source.lower()
    numbers = [int(token.replace("_", "")) for token in re.findall(r"(?<![\w.])\d[\d_]*(?![\w.])", source)]
    return ("bootstrap" in lowered and any(number >= 500 for number in numbers)
            and any(word in lowered for word in ("replace", "resample", "sample")))


def find_analysis_scripts():
    candidates = []
    excluded = {os.path.realpath(RUN_SIM), os.path.realpath(__file__)}
    for root in ("/home/user", "/root", "/app", "/tmp"):
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {"__pycache__", ".pytest_cache", ".git", "site-packages"}]
            for filename in files:
                path = os.path.realpath(os.path.join(directory, filename))
                if path in excluded or path == os.path.realpath(INTEGRATOR):
                    continue
                if not (filename.endswith((".py", ".R", ".r", ".sh")) or os.access(path, os.X_OK)):
                    continue
                try:
                    if os.path.getsize(path) > 2_000_000:
                        continue
                    with open(path, "r", encoding="utf-8", errors="ignore") as handle:
                        source = handle.read()
                except OSError:
                    continue
                lowered = source.lower()
                if ("analysis.json" in lowered or "estimated_k" in lowered) and has_bootstrap_evidence(path, source):
                    candidates.append(path)
    return sorted(set(candidates))


def run_analysis_script():
    candidates = find_analysis_scripts()
    assert candidates, "No analysis script implementing at least 500 bootstrap resamples was found"
    failures = []
    for path in candidates:
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        if path.lower().endswith(".py"):
            command = ["python3", path]
        elif path.lower().endswith(".r"):
            if not shutil.which("Rscript"):
                continue
            command = ["Rscript", path]
        elif path.lower().endswith(".sh"):
            command = ["bash", path]
        else:
            command = [path]
        try:
            result = subprocess.run(command, cwd="/home/user", timeout=120,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        except Exception as exc:
            failures.append(f"{path}: {exc}")
            continue
        if result.returncode == 0 and os.path.isfile(JSON_PATH):
            return path
        failures.append(f"{path}: exit {result.returncode}: {result.stderr[-500:]}")
    raise AssertionError("No qualifying analysis script regenerated analysis.json. " + "; ".join(failures))


def finite_number(value, field):
    assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{field} must be numeric"
    value = float(value)
    assert math.isfinite(value), f"{field} must be finite"
    return value


def test_final_state():
    assert_integrator_source_fixed()
    assert_package_installed()

    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(["python3", RUN_SIM], cwd="/home/user", timeout=60,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert result.returncode == 0, f"run_sim.py failed: {result.stderr[-1000:]}"

    actual = load_csv()
    t_sim, y_sim = expected_simulation()
    expected = np.column_stack((t_sim, y_sim))
    assert actual.shape == expected.shape, (
        f"Simulation CSV shape {actual.shape} does not match fixed integrator output {expected.shape}"
    )
    assert np.allclose(actual, expected, rtol=1e-9, atol=1e-10), (
        "Simulation CSV does not match output from the corrected adaptive integrator"
    )

    run_analysis_script()

    def reject_constant(token):
        raise ValueError(f"Non-standard JSON numeric constant: {token}")

    with open(JSON_PATH, "r", encoding="utf-8") as handle:
        data = json.load(handle, parse_constant=reject_constant)

    assert "estimated_k" in data, "JSON missing 'estimated_k'"
    assert "better_model" in data, "JSON missing 'better_model'"
    assert "ci_95_lower" in data, "JSON missing 'ci_95_lower'"
    assert "ci_95_upper" in data, "JSON missing 'ci_95_upper'"

    estimated_k = finite_number(data["estimated_k"], "estimated_k")
    ci_lower = finite_number(data["ci_95_lower"], "ci_95_lower")
    ci_upper = finite_number(data["ci_95_upper"], "ci_95_upper")
    better_model = data["better_model"]

    popt, _ = curve_fit(exp_model, t_sim, y_sim[:, 0], p0=(10.0, 0.5), maxfev=10000)
    k_true = float(popt[1])

    assert better_model == "exponential", f"Expected 'better_model' to be 'exponential', got '{better_model}'"
    error = abs(estimated_k - k_true)
    assert error < 0.05, (
        f"Metric failed: Absolute difference between estimated_k and k_true is {error:.4f}, "
        f"which is >= threshold 0.05. (estimated_k={estimated_k}, k_true={k_true:.4f})"
    )

    assert 0 <= ci_lower < ci_upper, "The 95% confidence interval must be finite, positive, and non-empty"
    assert ci_lower <= estimated_k <= ci_upper, "The 95% confidence interval must contain estimated_k"
    assert ci_upper - ci_lower < max(0.5, 1.5 * abs(estimated_k)), "The confidence interval is implausibly broad"

    linear_coef = np.polyfit(actual[:, 0], actual[:, 1], 1)
    linear_pred = np.polyval(linear_coef, actual[:, 0])
    fitted, _ = curve_fit(exp_model, actual[:, 0], actual[:, 1], p0=(10.0, 0.5), maxfev=10000)
    exp_pred = exp_model(actual[:, 0], *fitted)
    expected_better = "exponential" if np.mean((actual[:, 1] - exp_pred) ** 2) < np.mean((actual[:, 1] - linear_pred) ** 2) else "linear"
    assert better_model == expected_better, "better_model does not agree with MSE comparison on the generated CSV"

    # Ensure executing the analysis did not undo the package repair.
    assert_integrator_source_fixed()


if __name__ == "__main__":
    test_final_state()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
