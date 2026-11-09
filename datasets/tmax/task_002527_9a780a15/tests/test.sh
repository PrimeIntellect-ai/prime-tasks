#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import dis
import json
import math
import os
import runpy
import signal
import sys
import time

import numpy as np
import pandas as pd

PIPELINE = "/home/user/pipeline.py"
REPORT = "/home/user/report.json"
RAW = "/home/user/raw_features.csv"
WEIGHTS = "/home/user/weights.npy"
EXPECTED_KEYS = {"max_abs_error", "cleaned_data_mean", "inference_time_sec"}


def expected_metrics(data):
    x64 = np.asarray(data, dtype=np.float64)
    x64 = np.clip(x64, -10.0, 10.0)
    clean64 = 1.0 / (1.0 + np.exp(-x64))

    x32 = np.asarray(data, dtype=np.float32)
    x32 = np.clip(x32, np.float32(-10.0), np.float32(10.0))
    clean32 = np.float32(1.0) / (np.float32(1.0) + np.exp(-x32))

    return float(np.max(np.abs(clean64 - clean32))), float(np.mean(clean64))


def load_and_check_report(data, elapsed):
    assert os.path.isfile(REPORT), f"Missing report file: {REPORT}"
    with open(REPORT, "r") as f:
        report = json.load(f)

    assert set(report) == EXPECTED_KEYS, "report.json must contain exactly the requested keys"
    for key in EXPECTED_KEYS:
        assert type(report[key]) is float, f"Key '{key}' must be a JSON float"
        assert math.isfinite(report[key]), f"Key '{key}' must be finite"

    expected_err, expected_mean = expected_metrics(data)
    assert abs(report["cleaned_data_mean"] - expected_mean) <= 1e-10, (
        f"Incorrect cleaned_data_mean: expected {expected_mean}, got {report['cleaned_data_mean']}"
    )
    err_tol = max(2e-10, expected_err * 0.01)
    assert abs(report["max_abs_error"] - expected_err) <= err_tol, (
        f"Incorrect max_abs_error: expected {expected_err}, got {report['max_abs_error']}"
    )
    assert report["inference_time_sec"] > 0, "inference_time_sec must be greater than 0"
    assert report["inference_time_sec"] <= elapsed + 1.0, "Reported inference time exceeds total execution time"
    return report


def run_pipeline(data):
    counters = {"np_dot": 0, "np_matmul": 0, "pd_dot": 0, "series_dot": 0,
                "matmul_opcode": 0, "c_dot": 0, "prediction_sigmoid": 0}
    instruction_cache = {}

    original_dot = np.dot
    original_matmul = np.matmul
    original_exp = np.exp
    original_df_dot = pd.DataFrame.dot
    original_series_dot = pd.Series.dot

    def agent_caller():
        try:
            filename = sys._getframe(2).f_code.co_filename
        except ValueError:
            return False
        return os.path.abspath(filename).startswith("/home/user/")

    def wrapped_dot(*args, **kwargs):
        if agent_caller():
            counters["np_dot"] += 1
        return original_dot(*args, **kwargs)

    def wrapped_matmul(*args, **kwargs):
        if agent_caller():
            counters["np_matmul"] += 1
        return original_matmul(*args, **kwargs)

    def wrapped_exp(value, *args, **kwargs):
        if agent_caller():
            try:
                arr = np.asarray(value)
                if arr.size == 1000 and arr.ndim <= 2:
                    counters["prediction_sigmoid"] += 1
            except Exception:
                pass
        return original_exp(value, *args, **kwargs)

    def wrapped_df_dot(self, *args, **kwargs):
        if agent_caller():
            counters["pd_dot"] += 1
        return original_df_dot(self, *args, **kwargs)

    def wrapped_series_dot(self, *args, **kwargs):
        if agent_caller():
            counters["series_dot"] += 1
        return original_series_dot(self, *args, **kwargs)

    def is_agent_frame(frame):
        return os.path.abspath(frame.f_code.co_filename).startswith("/home/user/")

    def tracer(frame, event, arg):
        if event == "call" and is_agent_frame(frame):
            frame.f_trace_opcodes = True
            return tracer
        if event == "opcode" and is_agent_frame(frame):
            code = frame.f_code
            offsets = instruction_cache.get(code)
            if offsets is None:
                offsets = {i.offset: i for i in dis.get_instructions(code)}
                instruction_cache[code] = offsets
            inst = offsets.get(frame.f_lasti)
            if inst and (inst.opname == "BINARY_MATRIX_MULTIPLY" or
                         (inst.opname == "BINARY_OP" and inst.argrepr == "@")):
                counters["matmul_opcode"] += 1
        return tracer

    def profiler(frame, event, arg):
        if event == "c_call" and is_agent_frame(frame) and getattr(arg, "__name__", "") == "dot":
            counters["c_dot"] += 1

    def timeout_handler(signum, frame):
        raise TimeoutError("pipeline.py exceeded the 60 second execution limit")

    np.dot = wrapped_dot
    np.matmul = wrapped_matmul
    np.exp = wrapped_exp
    pd.DataFrame.dot = wrapped_df_dot
    pd.Series.dot = wrapped_series_dot
    old_argv = sys.argv[:]
    old_cwd = os.getcwd()
    old_handler = signal.signal(signal.SIGALRM, timeout_handler)
    signal.alarm(60)
    if os.path.exists(REPORT):
        os.remove(REPORT)

    start = time.perf_counter()
    try:
        os.chdir("/home/user")
        sys.argv = [PIPELINE]
        sys.settrace(tracer)
        sys.setprofile(profiler)
        try:
            runpy.run_path(PIPELINE, run_name="__main__")
        except SystemExit as exc:
            assert exc.code in (None, 0), f"pipeline.py exited with status {exc.code}"
    finally:
        elapsed = time.perf_counter() - start
        sys.settrace(None)
        sys.setprofile(None)
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old_handler)
        sys.argv = old_argv
        os.chdir(old_cwd)
        np.dot = original_dot
        np.matmul = original_matmul
        np.exp = original_exp
        pd.DataFrame.dot = original_df_dot
        pd.Series.dot = original_series_dot

    matrix_counts = [counters[k] for k in
                     ("np_dot", "np_matmul", "pd_dot", "series_dot", "matmul_opcode", "c_dot")]
    assert any(count == 1000 for count in matrix_counts), (
        "The executed pipeline must perform the model matrix multiplication exactly 1,000 times; "
        f"observed counters were {counters}"
    )
    assert counters["prediction_sigmoid"] >= 1000, (
        "The executed pipeline must apply sigmoid to the inference result in each of 1,000 iterations"
    )
    return load_and_check_report(data, elapsed)


def test_pipeline_and_report():
    assert os.path.isfile(PIPELINE), f"Missing pipeline script: {PIPELINE}"
    assert os.path.getsize(PIPELINE) > 0, "pipeline.py is empty"

    with open(RAW, "rb") as f:
        raw_backup = f.read()
    with open(WEIGHTS, "rb") as f:
        weights_backup = f.read()

    original_data = np.loadtxt(RAW, delimiter=",")
    original_report_bytes = None
    try:
        original_report = run_pipeline(original_data)
        with open(REPORT, "rb") as f:
            original_report_bytes = f.read()

        # Preserve the original verifier's deterministic assertions.
        assert abs(original_report["cleaned_data_mean"] - 0.501538) < 1e-4
        assert abs(original_report["max_abs_error"] - 5.96046e-08) < 1e-6
        assert original_report["inference_time_sec"] > 0

        rng = np.random.default_rng(73129)
        challenge = rng.normal(loc=-1.7, scale=8.3, size=(1000, 5))
        challenge[0] = [-1000.0, -10.0, 0.0, 10.0, 1000.0]
        challenge[1] = [-10.25, -9.75, 0.125, 9.75, 10.25]
        challenge_weights = rng.normal(size=5)
        np.savetxt(RAW, challenge, delimiter=",", fmt="%.18e")
        np.save(WEIGHTS, challenge_weights)
        run_pipeline(challenge)
    finally:
        with open(RAW, "wb") as f:
            f.write(raw_backup)
        with open(WEIGHTS, "wb") as f:
            f.write(weights_backup)
        if original_report_bytes is not None:
            with open(REPORT, "wb") as f:
                f.write(original_report_bytes)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
