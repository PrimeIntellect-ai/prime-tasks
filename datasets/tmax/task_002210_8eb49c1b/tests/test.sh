#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import time
import json
import math
import struct
import hashlib
import subprocess
import importlib
import importlib.machinery
import pytest
import numpy as np
from scapy.all import rdpcap, UDP

PACKAGE_DIR = "/app/vendored/fast_sensor_calc-0.1.0"
PCAP_PATH = "/app/data/sensor_stream.pcap"
SCRIPT_PATH = "/home/user/run_analysis.py"
OUTPUT_PATH = "/home/user/output_variances.txt"


def test_setup_py_fixed():
    setup_path = "/app/vendored/fast_sensor_calc-0.1.0/setup.py"
    assert os.path.exists(setup_path), f"setup.py is missing at {setup_path}"
    with open(setup_path, 'r') as f:
        content = f.read()
    assert "src/math_utils.c" in content, "setup.py is still missing 'src/math_utils.c' in the sources list. The C-extension cannot build correctly without it."


def test_extension_builds_and_is_numerically_stable():
    res = subprocess.run(
        [sys.executable, "-m", "pip", "install", "-e", PACKAGE_DIR,
         "--force-reinstall", "--no-deps"],
        cwd=PACKAGE_DIR,
        timeout=120,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"The vendored extension still fails to build/install:\n{res.stdout}\n{res.stderr}"

    importlib.invalidate_caches()
    sys.modules.pop("fast_sensor_calc", None)
    module = importlib.import_module("fast_sensor_calc")
    module_path = os.path.realpath(module.__file__)
    assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        f"fast_sensor_calc is not a compiled Python extension: {module_path}"
    assert callable(getattr(module, "compute_window_variance", None)), \
        "The compiled extension does not expose compute_window_variance"

    # High-magnitude, low-variance inputs make the original E[x^2]-E[x]^2
    # implementation fail badly. Derive the reference independently using fsum.
    cases = [
        [100000000.0 + x for x in ([-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0] * 257)],
        [100000000.0 + ((i % 17) - 8) * 0.125 for i in range(4096)],
        [100000000.0 + math.sin(i * 0.37) * 1.5 for i in range(3001)],
    ]
    for values in cases:
        mean = math.fsum(values) / len(values)
        expected = math.fsum((x - mean) * (x - mean) for x in values) / len(values)
        actual = module.compute_window_variance(values)
        assert math.isfinite(actual), f"Extension returned non-finite variance {actual}"
        tolerance = max(1e-7, abs(expected) * 1e-7)
        assert abs(actual - expected) <= tolerance, \
            f"Compiled extension is numerically unstable: expected {expected}, got {actual}"


def test_run_analysis_and_check_output():
    script_path = "/home/user/run_analysis.py"
    output_path = "/home/user/output_variances.txt"
    pcap_path = "/app/data/sensor_stream.pcap"

    assert os.path.exists(script_path), f"Script {script_path} does not exist."

    # Remove output if it exists to ensure we are testing the script's execution
    if os.path.exists(output_path):
        os.remove(output_path)

    start_time = time.time()
    try:
        res = subprocess.run(["python3", script_path], timeout=10, capture_output=True, text=True)
    except subprocess.TimeoutExpired:
        pytest.fail("Execution timed out. The script took longer than 10 seconds.")

    duration = time.time() - start_time

    assert res.returncode == 0, f"Script failed with error:\n{res.stderr}"
    assert duration < 5.0, f"Execution took too long ({duration:.2f}s). Expected < 5.0s. Make sure you are using the C-extension and not pure Python for the math."

    assert os.path.exists(output_path), f"Output file {output_path} was not created by the script."

    # Read Gold Reference
    packets = rdpcap(pcap_path)
    gold_variances = []
    for p in packets:
        if UDP in p and p[UDP].dport == 5000:
            payload = bytes(p[UDP].payload)
            count = len(payload) // 8
            floats = struct.unpack(f'<{count}d', payload)
            gold_variances.append(np.var(floats, ddof=0))

    # Read Agent Output
    with open(output_path, 'r') as f:
        agent_lines = f.read().strip().split('\n')

    assert len(agent_lines) == len(gold_variances), f"Row count mismatch. Expected {len(gold_variances)}, got {len(agent_lines)}"

    agent_variances = []
    for val in agent_lines:
        try:
            agent_variances.append(float(val))
        except ValueError:
            pytest.fail(f"Invalid float in output: {val}")

    # Compute MSE
    mse = np.mean((np.array(gold_variances) - np.array(agent_variances))**2)

    threshold = 1e-6
    assert mse < threshold, f"MSE {mse} exceeds threshold {threshold}. The numerical instability in the C-extension was not properly fixed."


def test_analysis_uses_extension_results_for_each_window(tmp_path):
    """Instrument the extension so bypassing it with NumPy cannot pass."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    tracker_path = tmp_path / "extension_calls.json"
    hook_dir = tmp_path / "hook"
    hook_dir.mkdir()
    hook = hook_dir / "sitecustomize.py"
    hook.write_text(r'''
import atexit
import hashlib
import json
import os
import struct
import fast_sensor_calc

_calls = []
_tracker = os.environ["FAST_SENSOR_TRACKER"]

def _tracked_variance(values):
    vals = [float(x) for x in values]
    packed = struct.pack("<%dd" % len(vals), *vals)
    _calls.append(hashlib.sha256(packed).hexdigest())
    # Return a deterministic sentinel derived from the supplied window. The
    # verifier checks that this exact return value reaches the output file.
    return vals[0] - 99990000.0

fast_sensor_calc.compute_window_variance = _tracked_variance

@atexit.register
def _save_calls():
    with open(_tracker, "w") as f:
        json.dump({"calls": _calls, "module": fast_sensor_calc.__file__}, f)
''')

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = str(hook_dir) + (os.pathsep + old_pythonpath if old_pythonpath else "")
    env["FAST_SENSOR_TRACKER"] = str(tracker_path)
    res = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        env=env,
        timeout=15,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"Instrumented analysis run failed:\n{res.stderr}"
    assert tracker_path.exists(), "The analysis process did not load the fast_sensor_calc instrumentation"
    assert os.path.exists(OUTPUT_PATH), "Instrumented analysis run did not create the output file"

    expected_digests = []
    expected_outputs = []
    for packet in rdpcap(PCAP_PATH):
        if UDP in packet and packet[UDP].dport == 5000:
            payload = bytes(packet[UDP].payload)
            count = len(payload) // 8
            values = struct.unpack(f"<{count}d", payload)
            expected_digests.append(hashlib.sha256(payload).hexdigest())
            expected_outputs.append(values[0] - 99990000.0)

    with open(tracker_path) as f:
        tracking = json.load(f)
    module_path = os.path.realpath(tracking["module"])
    assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        f"The analysis imported something other than the compiled extension: {module_path}"

    observed_calls = tracking["calls"]
    missing = set(expected_digests) - set(observed_calls)
    assert not missing, \
        f"The analysis did not pass every captured UDP window to compute_window_variance ({len(missing)} missing)"

    with open(OUTPUT_PATH) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == len(expected_outputs), \
        f"Row count mismatch during extension-use check: expected {len(expected_outputs)}, got {len(lines)}"
    try:
        observed_outputs = [float(line) for line in lines]
    except ValueError as exc:
        pytest.fail(f"Invalid float in instrumented output: {exc}")

    assert np.allclose(observed_outputs, expected_outputs, rtol=0.0, atol=1e-9), \
        "Output does not use the values returned by fast_sensor_calc.compute_window_variance"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
