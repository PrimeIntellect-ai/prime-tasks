#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import os
import random
import re
import stat
import subprocess
import sys

import numpy as np
import pytest

WORKSPACE_DIR = "/home/user/sim_pipeline"
GENERATE_DATA_EXE = os.path.join(WORKSPACE_DIR, "generate_data")
DATASET_TXT = os.path.join(WORKSPACE_DIR, "dataset.txt")
OPTIMIZER_PY = os.path.join(WORKSPACE_DIR, "optimizer.py")
EVALUATE_SH = os.path.join(WORKSPACE_DIR, "evaluate.sh")
FINAL_MSE_TXT = os.path.join(WORKSPACE_DIR, "final_mse.txt")
EXPECTED_DATASET = [
    (10.0, 10.0),
    (-10.0, 15.0),
    (0.0, -20.0),
    (100.0, -100.0),
    (-50.0, 50.0),
]


def parse_two_floats(output):
    parts = output.strip().split()
    assert len(parts) == 2, f"optimizer.py should print exactly two values (x y). Got: '{output.strip()}'"
    try:
        values = (float(parts[0]), float(parts[1]))
    except ValueError:
        pytest.fail(f"optimizer.py output non-float values: '{output.strip()}'")
    assert all(math.isfinite(v) for v in values), f"optimizer.py returned non-finite values: {values}"
    return values


def read_dataset(path):
    with open(path, "r") as f:
        content = f.read().strip()
    assert len(content) > 0, f"{path} is empty."
    rows = []
    for line in content.split("\n"):
        parts = line.strip().split()
        assert len(parts) == 2, f"Invalid format in dataset.txt: '{line}'"
        try:
            rows.append((float(parts[0]), float(parts[1])))
        except ValueError:
            pytest.fail(f"Non-float values in dataset.txt: '{line}'")
    return rows


def run_optimizer(x0, y0):
    try:
        result = subprocess.run(
            ["python3", OPTIMIZER_PY, str(x0), str(y0)],
            capture_output=True,
            text=True,
            check=True,
            timeout=45,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"optimizer.py failed for initial condition ({x0}, {y0}): {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"optimizer.py timed out for initial condition ({x0}, {y0})")
    return parse_two_floats(result.stdout)


def test_generate_data_compiled_and_run():
    assert os.path.isfile(GENERATE_DATA_EXE), f"{GENERATE_DATA_EXE} not found. Did you compile generate_data.c?"
    assert os.access(GENERATE_DATA_EXE, os.X_OK), f"{GENERATE_DATA_EXE} is not executable."
    with open(GENERATE_DATA_EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "generate_data must be a compiled executable, not a script."

    assert os.path.isfile(DATASET_TXT), f"{DATASET_TXT} not found. Did you run the generator and redirect output?"
    rows = read_dataset(DATASET_TXT)
    assert rows == EXPECTED_DATASET, f"dataset.txt does not contain the generator's expected points: {rows}"

    generated = subprocess.run(
        [GENERATE_DATA_EXE], capture_output=True, text=True, check=True, timeout=10
    ).stdout
    generated_rows = []
    for line in generated.strip().splitlines():
        parts = line.split()
        assert len(parts) == 2, f"generate_data emitted an invalid row: {line!r}"
        generated_rows.append((float(parts[0]), float(parts[1])))
    assert generated_rows == EXPECTED_DATASET, "generate_data emitted unexpected data."
    assert generated.strip() == open(DATASET_TXT).read().strip(), "dataset.txt was not produced from generate_data output."


def test_objective_is_exact_and_numerically_stable():
    spec = importlib.util.spec_from_file_location("submitted_optimizer", OPTIMIZER_PY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "objective") and callable(module.objective), "optimizer.py must define objective(vars)."

    rng = random.SystemRandom()
    points = [(3.14, -2.71), (100.0, -100.0), (-50.0, 50.0), (1e100, -1e100)]
    points.extend((rng.uniform(-200, 200), rng.uniform(-200, 200)) for _ in range(7))
    for x, y in points:
        a = 50.0 * (x - 3.14) ** 2
        b = 50.0 * (y + 2.71) ** 2
        expected = float(np.logaddexp(a, b))
        actual = float(module.objective([x, y]))
        assert math.isfinite(actual), f"objective overflowed or became non-finite at ({x}, {y}): {actual}"
        assert np.isclose(actual, expected, rtol=2e-14, atol=1e-10), (
            f"objective changed the required mathematical function at ({x}, {y}): "
            f"expected {expected}, got {actual}"
        )


def test_optimizer_py_cli():
    assert os.path.isfile(OPTIMIZER_PY), f"{OPTIMIZER_PY} not found."
    x_opt, y_opt = run_optimizer(100.0, -100.0)
    assert abs(x_opt - 3.14) < 1e-2, f"Optimized x is too far from 3.14: {x_opt}"
    assert abs(y_opt - (-2.71)) < 1e-2, f"Optimized y is too far from -2.71: {y_opt}"

    rng = random.SystemRandom()
    starts = [(rng.uniform(-120, 120), rng.uniform(-120, 120)) for _ in range(4)]
    for x0, y0 in starts:
        x_opt, y_opt = run_optimizer(x0, y0)
        assert abs(x_opt - 3.14) < 1e-2, f"Optimized x from ({x0}, {y0}) is too far from 3.14: {x_opt}"
        assert abs(y_opt + 2.71) < 1e-2, f"Optimized y from ({x0}, {y0}) is too far from -2.71: {y_opt}"


def test_cli_uses_arguments_and_scipy_nelder_mead(tmp_path):
    rng = random.SystemRandom()
    x0, y0 = rng.uniform(-90, 90), rng.uniform(-90, 90)
    sx, sy = rng.uniform(20, 30), rng.uniform(-30, -20)
    capture = tmp_path / "minimize_call.json"
    wrapper = tmp_path / "run_wrapped.py"
    wrapper.write_text(
        "import json, runpy, sys\n"
        "import numpy as np\n"
        "import scipy.optimize\n"
        "from types import SimpleNamespace\n"
        f"capture = {str(capture)!r}\n"
        f"sentinel = np.array([{sx!r}, {sy!r}], dtype=float)\n"
        "def fake_minimize(fun, initial, *args, **kwargs):\n"
        "    method = kwargs.get('method')\n"
        "    if method is None and len(args) >= 2:\n"
        "        method = args[1]\n"
        "    payload = {'initial': [float(v) for v in initial], 'method': method, "
        "'objective_at_initial': float(fun(initial))}\n"
        "    with open(capture, 'w') as f: json.dump(payload, f)\n"
        "    return SimpleNamespace(x=sentinel, success=True, fun=float(fun(sentinel)))\n"
        "scipy.optimize.minimize = fake_minimize\n"
        f"sys.argv = [{OPTIMIZER_PY!r}, {str(x0)!r}, {str(y0)!r}]\n"
        f"runpy.run_path({OPTIMIZER_PY!r}, run_name='__main__')\n"
    )
    result = subprocess.run(["python3", str(wrapper)], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Wrapped optimizer execution failed: {result.stderr}"
    out_x, out_y = parse_two_floats(result.stdout)
    assert np.allclose([out_x, out_y], [sx, sy], rtol=0, atol=1e-10), (
        "optimizer.py did not print the coordinates returned by scipy.optimize.minimize."
    )
    assert capture.is_file(), "optimizer.py did not call scipy.optimize.minimize."
    call = json.loads(capture.read_text())
    assert np.allclose(call["initial"], [x0, y0], rtol=0, atol=1e-12), (
        "optimizer.py did not pass the command-line coordinates as the initial guess."
    )
    assert str(call["method"]).lower().replace("_", "-") == "nelder-mead", (
        f"optimizer.py must retain the Nelder-Mead method, got {call['method']!r}."
    )
    expected = float(np.logaddexp(50 * (x0 - 3.14) ** 2, 50 * (y0 + 2.71) ** 2))
    assert np.isclose(call["objective_at_initial"], expected, rtol=2e-14, atol=1e-10)


def test_evaluate_sh_exists_and_executable():
    assert os.path.isfile(EVALUATE_SH), f"{EVALUATE_SH} not found."
    assert os.access(EVALUATE_SH, os.X_OK), f"{EVALUATE_SH} is not executable. Run chmod +x."


def test_final_mse_format_and_value():
    assert os.path.isfile(FINAL_MSE_TXT), f"{FINAL_MSE_TXT} not found. Did evaluate.sh produce it?"
    with open(FINAL_MSE_TXT, "r") as f:
        content = f.read().strip()
    assert content.startswith("MSE:"), f"Invalid format in final_mse.txt. Expected 'MSE: <value>', got: '{content}'"
    try:
        mse_val = float(content.split(":")[1].strip())
    except (IndexError, ValueError):
        pytest.fail(f"Could not parse MSE value from final_mse.txt: '{content}'")
    assert mse_val < 1e-3, f"MSE is too high ({mse_val}). Optimization failed or function wasn't stable."


def test_evaluate_sh_reproducible():
    if os.path.exists(FINAL_MSE_TXT):
        os.remove(FINAL_MSE_TXT)
    try:
        subprocess.run([EVALUATE_SH], check=True, cwd=WORKSPACE_DIR, capture_output=True, text=True, timeout=180)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"evaluate.sh failed to run: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("evaluate.sh timed out")
    assert os.path.isfile(FINAL_MSE_TXT), "evaluate.sh did not create final_mse.txt"
    content = open(FINAL_MSE_TXT).read().strip()
    assert content.startswith("MSE:"), "Invalid format in final_mse.txt after running evaluate.sh"
    mse_val = float(content.split(":")[1].strip())
    assert mse_val < 1e-3, f"MSE is too high after running evaluate.sh: {mse_val}"


def test_evaluate_calls_optimizer_and_recomputes_mse(tmp_path):
    rng = random.SystemRandom()
    rows = [(rng.uniform(-40, 40), rng.uniform(-40, 40)) for _ in range(6)]
    dataset_backup = open(DATASET_TXT, "rb").read()
    optimizer_backup = open(OPTIMIZER_PY, "rb").read()
    optimizer_mode = stat.S_IMODE(os.stat(OPTIMIZER_PY).st_mode)
    final_backup = open(FINAL_MSE_TXT, "rb").read() if os.path.exists(FINAL_MSE_TXT) else None
    log_path = tmp_path / "probe_calls.jsonl"

    probe = '''#!/usr/bin/env python3
import json, os, sys
x, y = float(sys.argv[1]), float(sys.argv[2])
with open(os.environ["PROBE_LOG"], "a") as f:
    f.write(json.dumps([x, y]) + "\\n")
print(f"{x * 0.25 + 1.234567:.9f} {y * -0.4 - 0.765432:.9f}")
'''
    try:
        with open(DATASET_TXT, "w") as f:
            for x, y in rows:
                f.write(f"{x:.9f} {y:.9f}\n")
        with open(OPTIMIZER_PY, "w") as f:
            f.write(probe)
        os.chmod(OPTIMIZER_PY, 0o755)
        if os.path.exists(FINAL_MSE_TXT):
            os.remove(FINAL_MSE_TXT)
        env = os.environ.copy()
        env["PROBE_LOG"] = str(log_path)
        result = subprocess.run(
            [EVALUATE_SH], cwd=WORKSPACE_DIR, env=env,
            capture_output=True, text=True, timeout=60
        )
        assert result.returncode == 0, f"evaluate.sh failed with controlled optimizer: {result.stderr}"
        assert log_path.is_file(), "evaluate.sh did not invoke optimizer.py."
        calls = [json.loads(line) for line in log_path.read_text().splitlines() if line.strip()]
        normalized_rows = [[float(f"{x:.9f}"), float(f"{y:.9f}")] for x, y in rows]
        assert calls == normalized_rows, "evaluate.sh must call optimizer.py once for each dataset row, in order."

        outputs = [
            (float(f"{x * 0.25 + 1.234567:.9f}"), float(f"{y * -0.4 - 0.765432:.9f}"))
            for x, y in normalized_rows
        ]
        expected_mse = sum(((x - 3.14) ** 2 + (y + 2.71) ** 2) / 2.0 for x, y in outputs) / len(outputs)
        expected_text = f"MSE: {expected_mse:.6f}"
        assert os.path.isfile(FINAL_MSE_TXT), "evaluate.sh did not create final_mse.txt"
        actual_text = open(FINAL_MSE_TXT).read().strip()
        assert re.fullmatch(r"MSE: [-+]?(?:\d+\.\d{6}|inf|nan)", actual_text), (
            f"final_mse.txt must use exactly six decimal places, got {actual_text!r}"
        )
        assert actual_text == expected_text, (
            f"evaluate.sh did not compute MSE from optimizer results: expected {expected_text!r}, got {actual_text!r}"
        )
    finally:
        with open(DATASET_TXT, "wb") as f:
            f.write(dataset_backup)
        with open(OPTIMIZER_PY, "wb") as f:
            f.write(optimizer_backup)
        os.chmod(OPTIMIZER_PY, optimizer_mode)
        if final_backup is None:
            if os.path.exists(FINAL_MSE_TXT):
                os.remove(FINAL_MSE_TXT)
        else:
            with open(FINAL_MSE_TXT, "wb") as f:
                f.write(final_backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
