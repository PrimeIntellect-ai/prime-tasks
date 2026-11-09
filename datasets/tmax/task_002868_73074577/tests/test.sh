#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import glob
import json
import math
import os
import random
import signal
import socket
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
import pytest
from scipy.integrate import solve_ivp

RESULT_PATH = "/home/user/submission_result.json"
SERVICE_SCRIPT = "/app/start_services.sh"


def test_submission_result_exists():
    assert os.path.isfile(RESULT_PATH), f"Expected submission result file at {RESULT_PATH} is missing."


def test_submission_result_mse():
    with open(RESULT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULT_PATH} is not valid JSON.")

    assert "mse" in data, f"Key 'mse' not found in {RESULT_PATH}. Found keys: {list(data.keys())}"
    mse_value = data["mse"]
    assert isinstance(mse_value, (int, float)), f"MSE value must be a number, got {type(mse_value)}"
    threshold = 0.05
    assert mse_value <= threshold, f"MSE {mse_value} is greater than the required threshold {threshold}."


def wait_http(url, timeout=20):
    import urllib.request
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=1) as response:
                if response.status == 200:
                    return json.loads(response.read().decode())
        except Exception as exc:
            last_error = exc
        time.sleep(0.25)
    raise AssertionError(f"Service at {url} did not become ready: {last_error}")


def test_start_services_fixed_and_running():
    assert os.path.isfile(SERVICE_SCRIPT), f"{SERVICE_SCRIPT} is missing."
    with open(SERVICE_SCRIPT, "r") as f:
        content = f.read()
    assert "REDIS_HOST" in content, "REDIS_HOST is still missing from start_services.sh"

    subprocess.run(["pkill", "-f", "uvicorn.*(lab_api|evaluator_api):app"], check=False)
    subprocess.run(["redis-cli", "shutdown"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)

    env = os.environ.copy()
    env.pop("REDIS_HOST", None)
    proc = subprocess.Popen(
        ["bash", SERVICE_SCRIPT], cwd="/app", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        start_new_session=True, text=True
    )
    try:
        sequences = wait_http("http://127.0.0.1:8000/sequences")
        assert isinstance(sequences, list) and len(sequences) == 5
        with socket.create_connection(("127.0.0.1", 6379), timeout=2):
            pass
        with socket.create_connection(("127.0.0.1", 8001), timeout=2):
            pass
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        subprocess.run(["pkill", "-f", "uvicorn.*(lab_api|evaluator_api):app"], check=False)
        time.sleep(0.5)


def ode_solution(times, gc, k1, k2):
    def rhs(t, y):
        p, a = y
        return [-k1 * p * a, k1 * p * a - k2 * a]
    sol = solve_ivp(rhs, [float(times[0]), float(times[-1])], [gc, 0.01], t_eval=times,
                    rtol=1e-8, atol=1e-10)
    assert sol.success and sol.y.shape[1] == len(times)
    return sol.y[1]


def make_challenge():
    rng = random.SystemRandom()
    gc_count = rng.choice([9, 10, 11, 12])
    primer = list("G" * (gc_count // 2) + "C" * (gc_count - gc_count // 2) +
                  "A" * ((20 - gc_count) // 2) + "T" * (20 - gc_count - (20 - gc_count) // 2))
    rng.shuffle(primer)
    primer = "".join(primer)

    sequences = []
    bases = "ACGT"
    for row in range(5):
        seq = list(primer + "ACGTAC")
        # At most two of five rows differ at any position, preserving a unique consensus.
        for pos in range(20):
            if row in ((pos + 1) % 5, (pos + 3) % 5):
                choices = [b for b in bases if b != primer[pos]]
                seq[pos] = choices[(row + pos) % len(choices)]
        sequences.append("".join(seq))

    consensus = "".join(collections.Counter(s[i] for s in sequences).most_common(1)[0][0]
                            for i in range(20))
    gc = 100.0 * sum(b in "GC" for b in consensus) / 20.0
    assert consensus == primer

    times = np.linspace(0, 100, 50)
    k1 = rng.uniform(0.065, 0.095)
    k2 = rng.uniform(0.015, 0.028)
    fluorescence = ode_solution(times, gc, k1, k2)
    return sequences, times, fluorescence, gc, k1, k2


def candidate_scripts():
    paths = []
    for root in ("/home/user", "/app"):
        for path in glob.glob(root + "/**/*.py", recursive=True):
            real = os.path.realpath(path)
            if real in ("/app/lab_api.py", "/app/evaluator_api.py"):
                continue
            if any(part in real for part in ("/.cache/", "/site-packages/", "/dist-packages/", "/__pycache__/")):
                continue
            if os.path.isfile(real) and os.path.getsize(real) <= 2_000_000:
                paths.append(real)
    return sorted(set(paths), key=lambda p: (os.path.getmtime(p), p))


def test_solution_script_queries_fits_submits_and_saves_exact_response():
    sequences, times, fluorescence, expected_gc, true_k1, true_k2 = make_challenge()
    nonce = uuid.uuid4().hex
    state = {"valid_responses": []}

    class Handler(BaseHTTPRequestHandler):
        def send_json(self, obj, status=200):
            body = json.dumps(obj, separators=(",", ":")).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path.split("?", 1)[0] == "/sequences":
                self.send_json(sequences)
            elif self.path.split("?", 1)[0] == "/kinetics":
                self.send_json({"time": times.tolist(), "fluorescence": fluorescence.tolist()})
            else:
                self.send_json({"detail": "not found"}, 404)

        def do_POST(self):
            if self.path.split("?", 1)[0] != "/submit":
                self.send_json({"detail": "not found"}, 404)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                payload = json.loads(self.rfile.read(length).decode())
                k1 = float(payload["k1"])
                k2 = float(payload["k2"])
                gc = float(payload["gc_content"])
                assert math.isfinite(k1) and math.isfinite(k2) and math.isfinite(gc)
                assert 0.001 <= k1 <= 1.0 and 0.001 <= k2 <= 1.0
                assert abs(gc - expected_gc) < 1e-8
                prediction = ode_solution(times, gc, k1, k2)
                mse = float(np.mean((ode_solution(times, expected_gc, true_k1, true_k2) - prediction) ** 2))
            except Exception:
                self.send_json({"status": "error", "mse": 1e9, "verification_nonce": nonce}, 200)
                return

            response = {"status": "success", "mse": mse, "verification_nonce": nonce}
            if mse < 0.05:
                state["valid_responses"].append(response)
            self.send_json(response)

        def log_message(self, *args):
            pass

    scripts = candidate_scripts()
    assert scripts, "No submitted Python solution script was found under /home/user or /app."

    servers = []
    threads = []
    try:
        for port in (8000, 8001):
            server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            servers.append(server)
            threads.append(thread)

        if os.path.exists(RESULT_PATH):
            os.unlink(RESULT_PATH)

        env = os.environ.copy()
        env["HOME"] = "/home/user"
        env["PYTHONUNBUFFERED"] = "1"
        for script in scripts[:30]:
            try:
                subprocess.run(
                    ["python3", script], cwd=os.path.dirname(script), env=env,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, timeout=90, check=False
                )
            except subprocess.TimeoutExpired:
                continue

            if state["valid_responses"] and os.path.isfile(RESULT_PATH):
                try:
                    with open(RESULT_PATH) as f:
                        saved = json.load(f)
                except Exception:
                    continue
                if saved == state["valid_responses"][-1]:
                    break

        assert state["valid_responses"], (
            "No submitted script queried the challenge and POSTed valid consensus-derived GC content "
            "and fitted ODE parameters with MSE < 0.05."
        )
        assert os.path.isfile(RESULT_PATH), "The executed solution did not save submission_result.json."
        with open(RESULT_PATH) as f:
            saved = json.load(f)
        assert saved == state["valid_responses"][-1], (
            "submission_result.json is not the exact JSON response returned for the valid submission."
        )
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
