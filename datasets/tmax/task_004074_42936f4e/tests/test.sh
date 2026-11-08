#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import re
import stat
import subprocess
import time
import urllib.request

import numpy as np
import pytest
from scipy.stats import gaussian_kde

RESULT = "/home/user/calibration_result.txt"
SCRIPT = "/home/user/calibrate.sh"
EVENTS = "/tmp/calibration_api_events"

SEQUENCER = '''from flask import Flask, jsonify
import numpy as np

app = Flask(__name__)

@app.route('/signal', methods=['GET'])
def get_signal():
    with open('/tmp/calibration_api_events', 'a') as f:
        f.write('signal\\n')
    np.random.seed(42)
    true_signal = np.random.normal(loc=0.0, scale=1.0, size=1000)
    target_scale = 1.45
    target_shift = -2.10
    raw = (true_signal - target_shift) / target_scale
    return jsonify({"signal": raw.tolist()})

if __name__ == '__main__':
    app.run(port=5000)
'''

SCORER = '''from flask import Flask, request, jsonify
import numpy as np
from scipy.stats import gaussian_kde
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/score', methods=['POST'])
def score():
    with open('/tmp/calibration_api_events', 'a') as f:
        f.write('score\\n')
    data = request.json
    raw = np.array(data['signal'])
    scale = float(data['scale'])
    shift = float(data['shift'])
    calibrated = raw * scale + shift
    kde = gaussian_kde(calibrated)
    x = np.linspace(-5, 5, 100)
    expected = np.exp(-0.5 * x**2) / np.sqrt(2 * np.pi)
    mse = float(np.mean((kde(x) - expected)**2))
    return jsonify({"mse": mse})

if __name__ == '__main__':
    app.run(port=5001)
'''

EXPECTED_HASHES = {}


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def request_json(url, payload=None):
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.loads(response.read().decode())


def setup_module(module):
    assert os.path.isfile(SCRIPT), f"Script file {SCRIPT} is missing"
    assert os.access(SCRIPT, os.X_OK), f"Script file {SCRIPT} is not executable"

    with open(SCRIPT, "rb") as f:
        first_line = f.readline().decode(errors="replace").strip()
    assert re.match(r"^#!.*\b(?:bash|env bash)\b", first_line), "calibrate.sh must be a Bash script"

    subprocess.run(["redis-cli", "shutdown", "nosave"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-f", "/app/sequencer[.]py"], check=False)
    subprocess.run(["pkill", "-f", "/app/scorer[.]py"], check=False)
    subprocess.run(["pkill", "-x", "redis-server"], check=False)
    time.sleep(1)

    with open("/app/sequencer.py", "w") as f:
        f.write(SEQUENCER)
    with open("/app/scorer.py", "w") as f:
        f.write(SCORER)
    EXPECTED_HASHES["/app/sequencer.py"] = sha256("/app/sequencer.py")
    EXPECTED_HASHES["/app/scorer.py"] = sha256("/app/scorer.py")

    for path in (RESULT, EVENTS):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    open(EVENTS, "w").close()
    os.chmod(EVENTS, 0o666)

    with open("/tmp/calibrate-output.log", "w") as log:
        try:
            completed = subprocess.run(
                [SCRIPT], stdout=log, stderr=subprocess.STDOUT, timeout=240, check=False
            )
        except subprocess.TimeoutExpired:
            pytest.fail("calibrate.sh did not finish within 240 seconds")
    assert completed.returncode == 0, f"calibrate.sh exited with status {completed.returncode}"

    assert sha256("/app/sequencer.py") == EXPECTED_HASHES["/app/sequencer.py"], "calibrate.sh modified the sequencer service"
    assert sha256("/app/scorer.py") == EXPECTED_HASHES["/app/scorer.py"], "calibrate.sh modified the scorer service"

    with open(EVENTS) as f:
        events = f.read().splitlines()
    assert "signal" in events, "calibrate.sh never fetched a signal from the Sequencer API"
    assert "score" in events, "calibrate.sh never submitted a candidate to the Scorer API"

    redis_ping = subprocess.run(["redis-cli", "ping"], text=True, capture_output=True, check=False)
    assert redis_ping.returncode == 0 and redis_ping.stdout.strip() == "PONG", "calibrate.sh did not start Redis"


def parse_result():
    with open(RESULT, "r") as f:
        content = f.read()
    strict = re.fullmatch(
        r"scale=([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)\n"
        r"shift=([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)\n"
        r"mse=([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)\n?",
        content,
    )
    assert strict, "calibration_result.txt must contain exactly scale, shift, and mse lines"
    values = tuple(float(v) for v in strict.groups())
    assert all(math.isfinite(v) for v in values), "Result values must be finite floats"
    return values


def test_calibration_result_exists_and_valid():
    result_file = "/home/user/calibration_result.txt"
    assert os.path.isfile(result_file), f"Result file {result_file} is missing"

    with open(result_file, 'r') as f:
        content = f.read()

    scale_match = re.search(r'scale=([0-9\.\-]+)', content)
    shift_match = re.search(r'shift=([0-9\.\-]+)', content)
    mse_match = re.search(r'mse=([0-9\.\-]+)', content)

    assert scale_match, "Format error: 'scale=<float>' not found in calibration_result.txt"
    assert shift_match, "Format error: 'shift=<float>' not found in calibration_result.txt"
    assert mse_match, "Format error: 'mse=<float>' not found in calibration_result.txt"

    try:
        scale = float(scale_match.group(1))
        shift = float(shift_match.group(1))
    except ValueError:
        pytest.fail("Could not parse scale or shift as floats.")

    target_scale = 1.45
    target_shift = -2.10
    error = (scale - target_scale)**2 + (shift - target_shift)**2
    assert error <= 0.02, f"Error metric {error:.5f} exceeds the threshold of 0.02. Found scale={scale}, shift={shift}"


def test_calibrate_script_exists_and_executable():
    script_file = "/home/user/calibrate.sh"
    assert os.path.isfile(script_file), f"Script file {script_file} is missing"
    assert os.access(script_file, os.X_OK), f"Script file {script_file} is not executable"


def test_result_against_live_services_and_recomputed_mse():
    scale, shift, reported_mse = parse_result()
    assert 0.1 <= scale <= 3.0, "scale is outside the valid range"
    assert -5.0 <= shift <= 5.0, "shift is outside the valid range"

    signal_response = request_json("http://localhost:5000/signal")
    raw = np.asarray(signal_response["signal"], dtype=float)
    scorer_response = request_json(
        "http://localhost:5001/score",
        {"signal": raw.tolist(), "scale": scale, "shift": shift},
    )
    api_mse = float(scorer_response["mse"])

    calibrated = raw * scale + shift
    x = np.linspace(-5, 5, 100)
    expected = np.exp(-0.5 * x**2) / np.sqrt(2 * np.pi)
    recomputed_mse = float(np.mean((gaussian_kde(calibrated)(x) - expected) ** 2))

    assert math.isfinite(api_mse) and math.isfinite(recomputed_mse)
    assert abs(api_mse - recomputed_mse) <= 1e-10, "Scorer response does not match an independent MSE computation"
    assert recomputed_mse < 0.02, f"Recomputed scorer MSE {recomputed_mse} is not strictly below 0.02"
    assert abs(reported_mse - recomputed_mse) <= 1e-6, "Reported mse does not match the MSE for the saved parameters"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
