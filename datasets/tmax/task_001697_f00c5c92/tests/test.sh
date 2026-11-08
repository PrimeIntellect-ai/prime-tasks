#!/bin/bash
set -e
mkdir -p /logs/verifier

rm -rf /tmp/verify_hook
mkdir -p /tmp/verify_hook

cat << 'HOOK_EOF' > /tmp/verify_hook/sitecustomize.py
import atexit
import json
import os
import time as _time

_EVENT_FILE = os.environ.get("VERIFY_EVENT_FILE")
_timing_calls = 0
_orig_time = _time.time
_orig_perf_counter = _time.perf_counter
_orig_process_time = _time.process_time


def _emit(obj):
    if not _EVENT_FILE:
        return
    try:
        line = json.dumps(obj, separators=(",", ":")) + "\n"
        fd = os.open(_EVENT_FILE, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
        try:
            os.write(fd, line.encode("utf-8"))
        finally:
            os.close(fd)
    except Exception:
        pass


def _wrap_clock(fn):
    def wrapped(*args, **kwargs):
        global _timing_calls
        _timing_calls += 1
        return fn(*args, **kwargs)
    return wrapped

_time.time = _wrap_clock(_orig_time)
_time.perf_counter = _wrap_clock(_orig_perf_counter)
_time.process_time = _wrap_clock(_orig_process_time)

try:
    import numpy as np
    import torch

    _orig_torch_load = torch.load
    _state = _orig_torch_load(
        "/home/user/workspace/model.pth", map_location="cpu", weights_only=True
    )
    _data = np.loadtxt("/home/user/workspace/data.csv", delimiter=",").astype(np.float32)
    _row_map = {row.tobytes(): i for i, row in enumerate(_data)}

    _first_w = next(v.detach().cpu() for v in _state.values()
                    if getattr(v, "ndim", 0) == 2 and tuple(v.shape) == (50, 10))
    _first_b = next(v.detach().cpu() for v in _state.values()
                    if getattr(v, "ndim", 0) == 1 and tuple(v.shape) == (50,))
    _second_w = next(v.detach().cpu() for v in _state.values()
                     if getattr(v, "ndim", 0) == 2 and tuple(v.shape) == (2, 50))
    _second_b = next(v.detach().cpu() for v in _state.values()
                     if getattr(v, "ndim", 0) == 1 and tuple(v.shape) == (2,))

    def checked_load(*args, **kwargs):
        path = os.fspath(args[0]) if args else os.fspath(kwargs.get("f"))
        _emit({"kind": "LOAD", "path": os.path.abspath(path)})
        return _orig_torch_load(*args, **kwargs)

    torch.load = checked_load
    _orig_linear_forward = torch.nn.Linear.forward
    _pending_hidden = None

    def checked_linear_forward(module, x):
        global _pending_hidden
        now = _orig_perf_counter()
        shape = tuple(module.weight.shape)
        grad_off = not torch.is_grad_enabled()

        if shape == (50, 10):
            xc = x.detach().cpu().to(torch.float32)
            rows = xc.numpy() if xc.ndim == 2 else np.empty((0, 10), dtype=np.float32)
            indices = [_row_map.get(np.asarray(row, dtype=np.float32).tobytes(), -1) for row in rows]
            weight_ok = (torch.allclose(module.weight.detach().cpu(), _first_w) and
                         module.bias is not None and
                         torch.allclose(module.bias.detach().cpu(), _first_b))
            _pending_hidden = torch.relu(xc @ _first_w.t() + _first_b)
            _emit({"kind": "F", "t": now, "n": len(indices), "indices": indices,
                   "weight_ok": bool(weight_ok), "grad_off": bool(grad_off)})
        elif shape == (2, 50):
            xc = x.detach().cpu().to(torch.float32)
            weight_ok = (torch.allclose(module.weight.detach().cpu(), _second_w) and
                         module.bias is not None and
                         torch.allclose(module.bias.detach().cpu(), _second_b))
            input_ok = (_pending_hidden is not None and
                        tuple(xc.shape) == tuple(_pending_hidden.shape) and
                        torch.allclose(xc, _pending_hidden, rtol=1e-4, atol=1e-6))
            _emit({"kind": "S", "t": now, "n": int(xc.shape[0]) if xc.ndim else 0,
                   "weight_ok": bool(weight_ok), "input_ok": bool(input_ok),
                   "grad_off": bool(grad_off)})
            _pending_hidden = None
        else:
            _emit({"kind": "O", "t": now, "shape": list(shape),
                   "grad_off": bool(grad_off)})
        return _orig_linear_forward(module, x)

    torch.nn.Linear.forward = checked_linear_forward
except Exception as exc:
    _emit({"kind": "HOOK_ERROR", "error": repr(exc)})


@atexit.register
def _report_timing_calls():
    _emit({"kind": "TIMING", "count": _timing_calls})
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import math
import os
import subprocess
import time

import numpy as np
import pytest

WORKSPACE_DIR = "/home/user/workspace"
BENCHMARK_CSV = os.path.join(WORKSPACE_DIR, "benchmark.csv")
BENCHMARK_PNG = os.path.join(WORKSPACE_DIR, "benchmark.png")
EXPERIMENT_LOG = os.path.join(WORKSPACE_DIR, "experiment_log.json")
PLOT_SCRIPT = os.path.join(WORKSPACE_DIR, "plot.py")
MODEL_PATH = os.path.join(WORKSPACE_DIR, "model.pth")
DATA_PATH = os.path.join(WORKSPACE_DIR, "data.csv")
EVENT_FILE = "/tmp/inference_events.jsonl"


def _remove_outputs():
    for path in (BENCHMARK_CSV, BENCHMARK_PNG, EXPERIMENT_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_artifacts():
    assert os.path.isfile(MODEL_PATH), f"{MODEL_PATH} is missing."
    assert os.path.isfile(DATA_PATH), f"{DATA_PATH} is missing."
    try:
        os.remove(EVENT_FILE)
    except FileNotFoundError:
        pass

    scripts = sorted(glob.glob(os.path.join(WORKSPACE_DIR, "**", "*.py"), recursive=True))
    assert scripts, "No Python script was provided for inference benchmarking."

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/verify_hook" + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["VERIFY_EVENT_FILE"] = EVENT_FILE
    env["MPLBACKEND"] = "Agg"

    chosen = None
    failures = []
    for script in scripts:
        _remove_outputs()
        started = time.perf_counter()
        try:
            result = subprocess.run(
                ["python3", script], cwd=WORKSPACE_DIR, env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                timeout=120
            )
        except subprocess.TimeoutExpired:
            failures.append(f"{script}: timed out")
            continue
        duration = time.perf_counter() - started
        if result.returncode == 0 and os.path.isfile(BENCHMARK_CSV) and os.path.isfile(EXPERIMENT_LOG):
            chosen = (script, duration)
            break
        failures.append(f"{script}: exit {result.returncode}: {result.stderr[-500:]}")

    assert chosen is not None, "No submitted Python script successfully generated both benchmark outputs. " + " | ".join(failures)

    assert os.path.isfile(PLOT_SCRIPT), f"{PLOT_SCRIPT} is missing."
    try:
        os.remove(BENCHMARK_PNG)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        ["python3", PLOT_SCRIPT], cwd=WORKSPACE_DIR, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120
    )
    assert result.returncode == 0, f"plot.py failed when executed headlessly: {result.stderr[-1000:]}"
    assert os.path.isfile(BENCHMARK_PNG), "Executing plot.py did not create benchmark.png."


def _read_csv_values():
    with open(BENCHMARK_CSV, newline="") as f:
        rows = list(csv.DictReader(f))
    return {int(row["batch_size"]): float(row["time_seconds"]) for row in rows}


def _events():
    assert os.path.isfile(EVENT_FILE), "No runtime instrumentation events were recorded."
    events = []
    with open(EVENT_FILE) as f:
        for line in f:
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return events


def _find_complete_run(model_events, batch_size):
    count = (1000 + batch_size - 1) // batch_size
    width = count * 2
    matches = []
    for start in range(0, len(model_events) - width + 1):
        segment = model_events[start:start + width]
        flattened = []
        sizes = []
        valid = True
        for i in range(count):
            first, second = segment[2 * i], segment[2 * i + 1]
            if first.get("kind") != "F" or second.get("kind") != "S":
                valid = False
                break
            if not (first.get("weight_ok") and first.get("grad_off") and
                    second.get("weight_ok") and second.get("input_ok") and second.get("grad_off")):
                valid = False
                break
            if first.get("n") != second.get("n") or not (1 <= first.get("n", 0) <= batch_size):
                valid = False
                break
            sizes.append(first["n"])
            flattened.extend(first.get("indices", []))
        if not valid:
            continue
        if sorted(sizes) != sorted([batch_size] * (count - 1) + [1000 - batch_size * (count - 1)]):
            continue
        if sorted(flattened) != list(range(1000)):
            continue
        matches.append(segment)
    assert matches, f"No complete, no-grad inference pass over all 1000 input rows was observed for batch size {batch_size}."
    return matches[-1]


def test_benchmark_csv_exists_and_valid():
    assert os.path.isfile(BENCHMARK_CSV), f"{BENCHMARK_CSV} is missing."

    with open(BENCHMARK_CSV, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["batch_size", "time_seconds"], f"Incorrect columns in {BENCHMARK_CSV}: {header}"

        rows = list(reader)
        assert len(rows) == 3, f"Expected exactly 3 data rows in {BENCHMARK_CSV}, found {len(rows)}"

        try:
            batch_sizes = [int(row[0]) for row in rows]
        except ValueError:
            assert False, "Batch sizes in the CSV must be integers."

        assert batch_sizes == [1, 32, 128], f"Expected batch sizes [1, 32, 128] in ascending order, found {batch_sizes}"

        for row in rows:
            try:
                value = float(row[1])
            except ValueError:
                assert False, f"Time value '{row[1]}' in {BENCHMARK_CSV} is not a valid float."
            assert math.isfinite(value) and value > 0, "Benchmark times must be positive finite values."


def test_runtime_model_reconstruction_and_inference():
    events = _events()
    assert not any(e.get("kind") == "HOOK_ERROR" for e in events), "Runtime verification hook failed."
    assert any(e.get("kind") == "LOAD" and e.get("path") == MODEL_PATH for e in events), \
        "The submitted benchmark script did not load model.pth with torch.load."
    assert sum(int(e.get("count", 0)) for e in events if e.get("kind") == "TIMING") >= 6, \
        "The benchmark script did not make enough clock readings to time all three inference runs."

    model_events = [e for e in events if e.get("kind") in {"F", "S", "O"}]
    csv_values = _read_csv_values()
    for batch_size in (1, 32, 128):
        segment = _find_complete_run(model_events, batch_size)
        observed_span = float(segment[-1]["t"]) - float(segment[0]["t"])
        reported = csv_values[batch_size]
        assert reported + 0.01 >= observed_span * 0.5, \
            f"Reported time for batch size {batch_size} is inconsistent with the observed inference run."
        assert reported <= observed_span * 5.0 + 0.1, \
            f"Reported time for batch size {batch_size} is inconsistent with the observed inference run."


def test_benchmark_png_exists_and_valid():
    assert os.path.isfile(BENCHMARK_PNG), f"{BENCHMARK_PNG} is missing."

    with open(BENCHMARK_PNG, "rb") as f:
        header = f.read(8)
        assert header == b'\x89PNG\r\n\x1a\n', f"{BENCHMARK_PNG} is not a valid PNG file."

    import matplotlib.image as mpimg
    image = mpimg.imread(BENCHMARK_PNG)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100, \
        "benchmark.png is not a usable rendered plot."
    assert np.isfinite(image).all() and float(np.std(image)) > 0.001, \
        "benchmark.png appears blank or corrupt."


def test_experiment_log_exists_and_valid():
    assert os.path.isfile(EXPERIMENT_LOG), f"{EXPERIMENT_LOG} is missing."

    with open(EXPERIMENT_LOG, "r") as f:
        try:
            log = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{EXPERIMENT_LOG} is not a valid JSON file."

    assert isinstance(log, dict), f"Expected JSON root to be a dictionary, found {type(log).__name__}"
    expected_keys = {"1", "32", "128"}
    assert set(log.keys()) == expected_keys, f"Expected keys {expected_keys} in {EXPERIMENT_LOG}, found {set(log.keys())}"

    csv_values = _read_csv_values()
    for k in expected_keys:
        assert isinstance(log[k], (float, int)) and not isinstance(log[k], bool), \
            f"Time value for key '{k}' in {EXPERIMENT_LOG} should be a number, found {type(log[k]).__name__}"
        assert math.isfinite(float(log[k])) and float(log[k]) > 0, \
            f"Time value for key '{k}' must be positive and finite."
        assert float(log[k]) == csv_values[int(k)], \
            f"Time for batch size {k} differs between benchmark.csv and experiment_log.json."


def test_plot_script_fixed():
    assert os.path.isfile(PLOT_SCRIPT), f"{PLOT_SCRIPT} is missing."

    with open(PLOT_SCRIPT, "r") as f:
        content = f.read()

    assert "plt.show()" not in content, "plot.py still contains 'plt.show()', which will fail in a headless environment."
    assert "benchmark.png" in content, "plot.py does not seem to contain the filename 'benchmark.png' to save the plot."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
