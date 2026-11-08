#!/bin/bash
set -e
mkdir -p /logs/verifier

# Replace the public data server with a verifier-controlled server so the
# submitted processor is exercised on a fresh 1000-point batch.
pkill -f '/home/user/pipeline/raw_server.py' >/dev/null 2>&1 || true
cat << 'SERVER_EOF' > /tmp/verifier_raw_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/data':
            self.send_response(404)
            self.end_headers()
            return
        try:
            with open('/tmp/verifier_raw_data.json', 'rb') as f:
                payload = f.read()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except Exception:
            self.send_response(500)
            self.end_headers()

    def log_message(self, *args):
        pass

class Server(HTTPServer):
    allow_reuse_address = True

Server(('127.0.0.1', 8081), Handler).serve_forever()
SERVER_EOF
python3 /tmp/verifier_raw_server.py >/tmp/verifier_raw_server.log 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true' EXIT
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

import matplotlib.image as mpimg
import numpy as np
import pytest

PIPELINE_DIR = "/home/user/pipeline"
PROCESSOR_SOURCE = os.path.join(PIPELINE_DIR, "processor.cpp")
PROCESSOR_BINARY = os.path.join(PIPELINE_DIR, "processor")
CLEANED_DATA_PATH = os.path.join(PIPELINE_DIR, "cleaned_data.csv")
REPORT_SCRIPT_PATH = os.path.join(PIPELINE_DIR, "start_report_service.sh")
REPORT_PNG_PATH = os.path.join(PIPELINE_DIR, "report.png")
RAW_TEST_PATH = "/tmp/verifier_raw_data.json"

EXPECTED = None

@pytest.fixture(scope="session", autouse=True)
def compile_and_run_processor():
    global EXPECTED

    assert os.path.isfile(PROCESSOR_SOURCE), f"Expected {PROCESSOR_SOURCE} to exist."

    rng = np.random.default_rng(secrets.randbits(64))
    raw = rng.normal(0.0, 5.0, 1000)
    indices = rng.permutation(1000)
    raw[indices[:50]] = -9999.0
    raw[indices[50:70]] = rng.choice([-25.0, -15.0, 20.0, 50.0], 20)

    valid_mean = np.mean(raw[raw != -9999.0])
    EXPECTED = raw.copy()
    EXPECTED[EXPECTED == -9999.0] = valid_mean
    EXPECTED = np.clip(EXPECTED, -10.0, 10.0)

    with open(RAW_TEST_PATH, "w") as f:
        json.dump(raw.tolist(), f)

    compile_result = subprocess.run(
        ["g++", "-O3", PROCESSOR_SOURCE, "-o", PROCESSOR_BINARY, "-lcurl"],
        cwd=PIPELINE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"processor.cpp did not compile:\n{compile_result.stdout}"
    assert os.path.isfile(PROCESSOR_BINARY), "Compilation did not produce the processor executable."

    if os.path.exists(CLEANED_DATA_PATH):
        os.remove(CLEANED_DATA_PATH)

    run_result = subprocess.run(
        [PROCESSOR_BINARY],
        cwd=PIPELINE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=20,
    )
    assert run_result.returncode == 0, f"The compiled processor failed:\n{run_result.stdout}"


def test_cleaned_data_exists():
    assert os.path.isfile(CLEANED_DATA_PATH), f"Expected {CLEANED_DATA_PATH} to exist, but it does not."


def test_cleaned_data_mse():
    assert os.path.isfile(CLEANED_DATA_PATH), "Cannot compute MSE because cleaned_data.csv is missing."

    try:
        agent_data = np.loadtxt(CLEANED_DATA_PATH)
    except Exception as e:
        pytest.fail(f"Failed to load agent's cleaned_data.csv: {e}")

    assert agent_data.shape == EXPECTED.shape, (
        f"Shape mismatch: agent data has shape {agent_data.shape}, "
        f"expected {EXPECTED.shape}."
    )

    mse = np.mean((agent_data - EXPECTED) ** 2)
    threshold = 0.001
    assert mse <= threshold, (
        f"MSE between cleaned_data.csv and expected cleaned data is {mse:.6f}, "
        f"which exceeds the threshold of {threshold}."
    )

    with open(CLEANED_DATA_PATH) as f:
        lines = [line.rstrip("\n") for line in f]
    assert len(lines) == 1000, "cleaned_data.csv must contain exactly 1000 lines."
    for number, line in enumerate(lines, 1):
        body = line[1:] if line.startswith(("+", "-")) else line
        pieces = body.split(".")
        assert len(pieces) == 2 and pieces[0].isdigit() and pieces[1].isdigit() and len(pieces[1]) == 4, (
            f"Line {number} is not a floating-point number formatted to exactly 4 decimal places: {line!r}"
        )


def test_report_png_exists_and_is_generated_by_fixed_service():
    assert os.path.isfile(REPORT_SCRIPT_PATH), f"Expected {REPORT_SCRIPT_PATH} to exist."
    assert os.access(REPORT_SCRIPT_PATH, os.X_OK), "start_report_service.sh is not executable."

    with open(REPORT_SCRIPT_PATH) as f:
        script = f.read()
    compact = script.lower().replace(" ", "").replace("\t", "").replace("'", "").replace('"', "")
    assert "mplbackend=agg" in compact, (
        "start_report_service.sh must configure Matplotlib's MPLBACKEND to Agg for headless operation."
    )

    if os.path.exists(REPORT_PNG_PATH):
        os.remove(REPORT_PNG_PATH)

    env = os.environ.copy()
    env.pop("MPLBACKEND", None)
    env.pop("DISPLAY", None)
    result = subprocess.run(
        [REPORT_SCRIPT_PATH],
        cwd=PIPELINE_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, f"The reporting service failed:\n{result.stdout}"
    assert os.path.isfile(REPORT_PNG_PATH), (
        f"Expected {REPORT_PNG_PATH} to exist, but it does not. Ensure the reporting service script was fixed and run."
    )

    with open(REPORT_PNG_PATH, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "report.png is not a valid PNG file."
    try:
        image = np.asarray(mpimg.imread(REPORT_PNG_PATH))
    except Exception as e:
        pytest.fail(f"Failed to decode report.png: {e}")
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10, "report.png has invalid dimensions."
    rgb = image[..., :3] if image.ndim == 3 else image
    assert np.isfinite(rgb).all() and float(np.std(rgb)) > 0.01, "report.png appears to be blank."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
