#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess
import urllib.error
import urllib.request

import cv2
import numpy as np
import pytest
from scipy.special import digamma, polygamma

TOKEN = "Bearer perf-token-2024"


def expected_result():
    np.random.seed(42)
    samples = np.round(np.random.gamma(shape=4.5, scale=3.2, size=120)).astype(int)
    assert np.all(samples > 0)
    mean = float(np.mean(samples))
    target = math.log(mean) - float(np.mean(np.log(samples)))
    k = max((3.0 - target + math.sqrt((target - 3.0) ** 2 + 24.0 * target)) / (12.0 * target), 1e-3)
    for _ in range(1000):
        f = math.log(k) - float(digamma(k)) - target
        fp = 1.0 / k - float(polygamma(1, k))
        new_k = k - f / fp
        if new_k <= 0 or not math.isfinite(new_k):
            new_k = k / 2.0
        if abs(new_k - k) < 1e-12:
            k = new_k
            break
        k = new_k
    return samples, k, mean / k


SAMPLES, EXPECTED_K, EXPECTED_THETA = expected_result()


def request(path, auth=None):
    headers = {}
    if auth is not None:
        headers["Authorization"] = auth
    req = urllib.request.Request("http://127.0.0.1:8000" + path, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8")
    except Exception as exc:
        pytest.fail(f"Failed to connect to the server: {exc}")


def parse_params(output):
    number = r"([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)"
    km = re.search(r"(?:\bk\b|shape(?:\s+parameter)?)[^\n\d+.-]*" + number, output, re.I)
    tm = re.search(r"(?:theta|scale(?:\s+parameter)?)[^\n\d+.-]*" + number, output, re.I)
    if km and tm:
        return float(km.group(1)), float(tm.group(1))
    values = re.findall(number, output)
    if len(values) >= 2:
        return float(values[-2]), float(values[-1])
    raise AssertionError(f"Could not parse k and theta from C program output: {output!r}")


def candidate_c_sources():
    found = []
    for root in ("/home/user", "/app", "/root", "/tmp", "/workspace"):
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".cache", ".git", "node_modules", "site-packages"}]
            for name in files:
                path = os.path.join(directory, name)
                if name.endswith(".c") and os.path.getsize(path) < 1000000:
                    found.append(path)
    return found


def run_c_implementation():
    sources = candidate_c_sources()
    assert sources, "No C source program implementing the Gamma fit was found."
    count_file = "/tmp/verifier_cache_misses.txt"
    with open(count_file, "w") as f:
        f.write("\n".join(map(str, SAMPLES)) + "\n")

    errors = []
    for index, source in enumerate(sources):
        text = open(source, errors="ignore").read()
        lower = text.lower()
        if "main" not in lower or not ("digamma" in lower or "gsl_sf_psi" in lower or re.search(r"\bpsi\s*\(", lower)):
            continue
        assert re.search(r"\b(for|while)\s*\(", lower), f"{source} does not contain an iterative Newton-Raphson solver."
        assert "fabs" in lower or "abs(" in lower, f"{source} does not check the absolute change in k."
        assert re.search(r"1e-0*6|1\.0e-0*6|0\.000001", lower), f"{source} does not use the required 1e-6 convergence criterion."

        binary = f"/tmp/verifier_fit_gamma_{index}"
        compile_cmd = ["gcc", source, "-O2", "-o", binary, "-lgsl", "-lgslcblas", "-lm"]
        compiled = subprocess.run(compile_cmd, cwd=os.path.dirname(source), text=True, capture_output=True)
        if compiled.returncode != 0:
            errors.append(f"{source}: compilation failed: {compiled.stderr[-1000:]}")
            continue

        invocations = [
            ([binary], None),
            ([binary, count_file], None),
            ([binary], "\n".join(map(str, SAMPLES)) + "\n"),
        ]
        for command, stdin_data in invocations:
            try:
                result = subprocess.run(command, cwd=os.path.dirname(source), input=stdin_data,
                                        text=True, capture_output=True, timeout=8)
            except subprocess.TimeoutExpired:
                continue
            if result.returncode != 0:
                continue
            try:
                k, theta = parse_params(result.stdout + "\n" + result.stderr)
            except (AssertionError, ValueError):
                continue
            if (math.isfinite(k) and math.isfinite(theta) and
                    math.isclose(k, EXPECTED_K, rel_tol=1e-2) and
                    math.isclose(theta, EXPECTED_THETA, rel_tol=1e-2)):
                return k, theta
            errors.append(f"{source}: produced k={k}, theta={theta}")

    pytest.fail("No compiled C implementation produced the MLE for the video dataset. " + " | ".join(errors[-4:]))


@pytest.fixture(scope="session")
def c_params():
    return run_c_implementation()


def test_video_has_120_frames():
    capture = cv2.VideoCapture("/app/system_monitor.mp4")
    count = 0
    while True:
        ok, _ = capture.read()
        if not ok:
            break
        count += 1
    capture.release()
    assert count == 120, f"Expected 120 video frames, found {count}."


def test_c_gamma_fit(c_params):
    k, theta = c_params
    assert math.isclose(k, EXPECTED_K, rel_tol=1e-2)
    assert math.isclose(theta, EXPECTED_THETA, rel_tol=1e-2)


def test_plot_exists_and_is_real():
    path = "/home/user/fit_plot.png"
    assert os.path.exists(path), "Visualization plot /home/user/fit_plot.png does not exist."
    assert os.path.getsize(path) > 1000, "Visualization plot is empty or implausibly small."
    image = cv2.imread(path, cv2.IMREAD_COLOR)
    assert image is not None, "fit_plot.png is not a valid PNG image."
    assert image.shape[0] >= 100 and image.shape[1] >= 100, "Visualization plot is implausibly small."
    assert float(np.std(image)) > 3.0, "Visualization plot contains no substantive graphics."


def test_server_ready_file():
    assert os.path.exists("/home/user/server_ready.txt"), "The marker file /home/user/server_ready.txt was not created."


def test_api_unauthorized():
    status, _ = request("/params")
    assert status == 401, f"Expected 401 Unauthorized without auth, got {status}."
    status, _ = request("/params", "Bearer wrong-token")
    assert status == 401, f"Expected 401 Unauthorized with an incorrect token, got {status}."


def test_api_params_are_c_results(c_params):
    status, body = request("/params", TOKEN)
    assert status == 200, f"Expected 200 OK, got {status}."
    try:
        data = json.loads(body)
    except Exception:
        pytest.fail(f"Failed to parse JSON from response: {body}")
    assert "k" in data, "Missing 'k' parameter in response."
    assert "theta" in data, "Missing 'theta' parameter in response."
    assert isinstance(data["k"], (int, float)) and math.isfinite(data["k"])
    assert isinstance(data["theta"], (int, float)) and math.isfinite(data["theta"])
    assert math.isclose(data["k"], EXPECTED_K, rel_tol=1e-2), f"Estimated k ({data['k']}) does not match the video dataset MLE ({EXPECTED_K})."
    assert math.isclose(data["theta"], EXPECTED_THETA, rel_tol=1e-2), f"Estimated theta ({data['theta']}) does not match the video dataset MLE ({EXPECTED_THETA})."
    assert math.isclose(data["k"], c_params[0], rel_tol=1e-6, abs_tol=1e-6)
    assert math.isclose(data["theta"], c_params[1], rel_tol=1e-6, abs_tol=1e-6)


def test_api_pdf():
    for x in (1.0, 15.0, 31.25):
        expected_pdf = (x ** (EXPECTED_K - 1.0) * math.exp(-x / EXPECTED_THETA)) / (EXPECTED_THETA ** EXPECTED_K * math.gamma(EXPECTED_K))
        status, body = request(f"/pdf?x={x}", TOKEN)
        assert status == 200, f"Expected 200 OK for x={x}, got {status}."
        try:
            data = json.loads(body)
        except Exception:
            pytest.fail(f"Failed to parse JSON from response: {body}")
        assert "pdf" in data, "Missing 'pdf' key in response."
        assert isinstance(data["pdf"], (int, float)) and math.isfinite(data["pdf"])
        assert math.isclose(data["pdf"], expected_pdf, rel_tol=1e-2, abs_tol=1e-12), f"Incorrect Gamma PDF at x={x}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
