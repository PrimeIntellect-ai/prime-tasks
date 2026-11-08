#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUN_EOF' > /tmp/run_submission.py
import inspect
import json
import os
import runpy

os.environ.setdefault("MPLBACKEND", "Agg")

import numpy as np
import scipy.integrate
import matplotlib.figure

meta_path = "/tmp/generate_data_execution.json"
t_ref = np.linspace(0.0, 10.0, 1000)

def rhs(t, y):
    return [y[1], -0.5 * y[1] - 2.0 * y[0]]

_original_solve_ivp = scipy.integrate.solve_ivp
_expected_solution = _original_solve_ivp(
    rhs, (0.0, 10.0), [1.0, 0.0], method="RK45",
    t_eval=t_ref, rtol=1e-8, atol=1e-8
)
x_num_ref = _expected_solution.y[0]
v_num_ref = _expected_solution.y[1]
omega_d = np.sqrt(1.9375)
x_ana_ref = np.exp(-0.25 * t_ref) * (
    np.cos(omega_d * t_ref) + (0.25 / omega_d) * np.sin(omega_d * t_ref)
)
v_ana_ref = np.gradient(x_ana_ref, t_ref)

metadata = {"solve_ivp_match": False, "gradient_match": False, "saves": []}
_solve_signature = inspect.signature(_original_solve_ivp)

def solve_ivp_wrapper(*args, **kwargs):
    try:
        bound = _solve_signature.bind_partial(*args, **kwargs)
        bound.apply_defaults()
        span = np.asarray(bound.arguments.get("t_span"), dtype=float)
        y0 = np.asarray(bound.arguments.get("y0"), dtype=float)
        te = np.asarray(bound.arguments.get("t_eval"), dtype=float)
        if (
            span.shape == (2,) and np.allclose(span, [0.0, 10.0], rtol=0, atol=1e-14)
            and y0.shape == (2,) and np.allclose(y0, [1.0, 0.0], rtol=0, atol=1e-14)
            and bound.arguments.get("method") == "RK45"
            and float(bound.arguments.get("rtol")) == 1e-8
            and float(bound.arguments.get("atol")) == 1e-8
            and te.shape == (1000,)
            and np.allclose(te, t_ref, rtol=0, atol=1e-14)
        ):
            metadata["solve_ivp_match"] = True
    except Exception:
        pass
    return _original_solve_ivp(*args, **kwargs)

scipy.integrate.solve_ivp = solve_ivp_wrapper
_original_gradient = np.gradient

def gradient_wrapper(*args, **kwargs):
    result = _original_gradient(*args, **kwargs)
    try:
        source = np.asarray(args[0], dtype=float)
        output = np.asarray(result, dtype=float)
        if (
            source.shape == (1000,)
            and output.shape == (1000,)
            and np.allclose(source, x_ana_ref, rtol=2e-8, atol=2e-10)
            and np.allclose(output, v_ana_ref, rtol=2e-7, atol=2e-8)
        ):
            metadata["gradient_match"] = True
    except Exception:
        pass
    return result

np.gradient = gradient_wrapper
_original_savefig = matplotlib.figure.Figure.savefig

def curve_present(axis, expected_y):
    for line in axis.lines:
        try:
            xd = np.asarray(line.get_xdata(), dtype=float)
            yd = np.asarray(line.get_ydata(), dtype=float)
            if (
                xd.shape == (1000,) and yd.shape == (1000,)
                and np.allclose(xd, t_ref, rtol=0, atol=2e-10)
                and np.allclose(yd, expected_y, rtol=3e-7, atol=3e-8)
            ):
                return True
        except Exception:
            pass
    return False

def savefig_wrapper(self, *args, **kwargs):
    fname = args[0] if args else kwargs.get("fname", "")
    axes = list(self.axes)
    record = {
        "path": os.path.abspath(os.fspath(fname)) if isinstance(fname, (str, bytes, os.PathLike)) else "",
        "axes_count": len(axes),
        "line_counts": [len(ax.lines) for ax in axes],
        "position_ok": False,
        "velocity_ok": False,
    }
    if len(axes) >= 2:
        record["position_ok"] = curve_present(axes[0], x_num_ref) and curve_present(axes[0], x_ana_ref)
        record["velocity_ok"] = curve_present(axes[1], v_num_ref) and curve_present(axes[1], v_ana_ref)
    metadata["saves"].append(record)
    return _original_savefig(self, *args, **kwargs)

matplotlib.figure.Figure.savefig = savefig_wrapper

try:
    runpy.run_path("/home/user/generate_data.py", run_name="__main__")
finally:
    with open(meta_path, "w") as f:
        json.dump(metadata, f)
RUN_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import subprocess

import numpy as np
import matplotlib.image as mpimg
from scipy.integrate import solve_ivp
import pytest

OUTPUTS = [
    '/home/user/oscillator_plot.png',
    '/home/user/training_data.csv',
    '/home/user/training_data_report.json',
    '/tmp/generate_data_execution.json',
]

@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    script = '/home/user/generate_data.py'
    assert os.path.isfile(script), "Script /home/user/generate_data.py not found or is not a regular file"
    assert os.path.getsize(script) > 0, "Script /home/user/generate_data.py is empty"
    for path in OUTPUTS:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    env = os.environ.copy()
    env['MPLBACKEND'] = 'Agg'
    result = subprocess.run(
        ['python3', '/tmp/run_submission.py'], cwd='/home/user', env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90
    )
    assert result.returncode == 0, (
        f"generate_data.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def expected_data():
    t = np.linspace(0.0, 10.0, 1000)
    def rhs(_, y):
        return [y[1], -0.5 * y[1] - 2.0 * y[0]]
    solution = solve_ivp(
        rhs, (0.0, 10.0), [1.0, 0.0], method='RK45',
        t_eval=t, rtol=1e-8, atol=1e-8
    )
    omega_d = np.sqrt(1.9375)
    x_ana = np.exp(-0.25 * t) * (
        np.cos(omega_d * t) + (0.25 / omega_d) * np.sin(omega_d * t)
    )
    v_ana = np.gradient(x_ana, t)
    return np.column_stack((t, solution.y[0], solution.y[1], x_ana, v_ana))


def test_script_exists():
    assert os.path.exists('/home/user/generate_data.py'), "Script /home/user/generate_data.py not found"


def test_plot_exists():
    assert os.path.exists('/home/user/oscillator_plot.png'), "Plot /home/user/oscillator_plot.png not found"


def test_csv_output():
    csv_path = '/home/user/training_data.csv'
    assert os.path.exists(csv_path), f"CSV file {csv_path} not found"

    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        expected_columns = ['t', 'x_num', 'v_num', 'x_ana', 'v_ana']
        assert header == expected_columns, f"CSV columns incorrect. Expected {expected_columns}, got {header}"

        rows = list(reader)
        assert len(rows) == 1000, f"CSV length incorrect. Expected 1000 rows, got {len(rows)}"


def test_csv_values_match_required_pipeline():
    with open('/home/user/training_data.csv', 'r') as f:
        reader = csv.reader(f)
        next(reader)
        rows = list(reader)
    assert all(len(row) == 5 for row in rows), "Every CSV row must contain exactly five values"
    try:
        actual = np.asarray([[float(value) for value in row] for row in rows], dtype=float)
    except ValueError as exc:
        pytest.fail(f"CSV contains a non-numeric value: {exc}")
    assert actual.shape == (1000, 5)
    assert np.isfinite(actual).all(), "CSV contains NaN or infinite values"
    expected = expected_data()
    np.testing.assert_allclose(actual[:, 0], expected[:, 0], rtol=0, atol=2e-10)
    np.testing.assert_allclose(actual[:, 1], expected[:, 1], rtol=3e-7, atol=3e-8)
    np.testing.assert_allclose(actual[:, 2], expected[:, 2], rtol=3e-7, atol=3e-8)
    np.testing.assert_allclose(actual[:, 3], expected[:, 3], rtol=3e-7, atol=3e-8)
    np.testing.assert_allclose(actual[:, 4], expected[:, 4], rtol=3e-7, atol=3e-8)


def test_json_report():
    json_path = '/home/user/training_data_report.json'
    assert os.path.exists(json_path), f"JSON file {json_path} not found"

    with open(json_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, "JSON file is not valid"

    assert 'mse_x' in report, "Key 'mse_x' missing in JSON report"
    assert 'mse_v' in report, "Key 'mse_v' missing in JSON report"

    mse_x = report['mse_x']
    mse_v = report['mse_v']

    assert isinstance(mse_x, (int, float)), "mse_x must be a number"
    assert isinstance(mse_v, (int, float)), "mse_v must be a number"

    assert mse_x < 1e-4, f"mse_x too high: {mse_x}. Expected < 1e-4"
    assert mse_v < 1e-2, f"mse_v too high: {mse_v}. Expected < 1e-2"


def test_json_values_are_recomputed_mse():
    with open('/home/user/training_data_report.json', 'r') as f:
        report = json.load(f)
    assert set(report.keys()) == {'mse_x', 'mse_v'}, "JSON report must contain exactly mse_x and mse_v"
    assert not isinstance(report['mse_x'], bool) and not isinstance(report['mse_v'], bool)
    values = np.genfromtxt('/home/user/training_data.csv', delimiter=',', skip_header=1)
    expected_mse_x = float(np.mean((values[:, 1] - values[:, 3]) ** 2))
    expected_mse_v = float(np.mean((values[:, 2] - values[:, 4]) ** 2))
    for key, expected in [('mse_x', expected_mse_x), ('mse_v', expected_mse_v)]:
        actual = float(report[key])
        assert np.isfinite(actual), f"{key} must be finite"
        assert actual >= 0.0, f"{key} must be non-negative"
        assert np.isclose(actual, expected, rtol=2e-6, atol=1e-14), (
            f"{key} does not equal the MSE recomputed from the exported data"
        )


def test_required_apis_were_exercised():
    with open('/tmp/generate_data_execution.json', 'r') as f:
        metadata = json.load(f)
    assert metadata['solve_ivp_match'], "Script did not call solve_ivp with the required interval, t_eval, method, and tolerances"
    assert metadata['gradient_match'], "Script did not use numpy.gradient on the required analytical position data"


def test_plot_is_valid_and_contains_required_curves():
    path = '/home/user/oscillator_plot.png'
    assert os.path.isfile(path) and os.path.getsize(path) > 1000, "Plot is empty or not a regular file"
    with open(path, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', "oscillator_plot.png is not a PNG image"
    image = mpimg.imread(path)
    assert image.ndim in (2, 3) and image.shape[0] >= 300 and image.shape[1] >= 300
    assert np.isfinite(image).all() and float(np.std(image)) > 0.01, "Plot image is blank or invalid"
    with open('/tmp/generate_data_execution.json', 'r') as f:
        metadata = json.load(f)
    saves = [s for s in metadata['saves'] if s['path'] == path]
    assert saves, "Script did not save the required plot path through matplotlib"
    record = saves[-1]
    assert record['axes_count'] == 2, "Plot must contain exactly two subplots"
    assert record['line_counts'][0] >= 2 and record['line_counts'][1] >= 2, "Each subplot must show both required series"
    assert record['position_ok'], "Position subplot does not contain x_num and x_ana versus time"
    assert record['velocity_ok'], "Velocity subplot does not contain v_num and v_ana versus time"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
