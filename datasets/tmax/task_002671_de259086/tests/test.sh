#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import signal
import subprocess
import time

import pytest
import requests
from pydub import AudioSegment
from pydub.silence import detect_silence

URL = "http://127.0.0.1:8080/metrics"
EXPECTED_KEYS = {
    "alpha_values",
    "beta_values",
    "t_test_p_value",
    "bayesian_posterior_mean",
    "bayesian_ci_lower",
    "bayesian_ci_upper",
}


def get_metrics(timeout=5):
    try:
        response = requests.get(URL, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the web service at {URL}. Is the server running? Error: {exc}")
    assert response.status_code == 200, (
        f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert isinstance(data, dict), "The JSON response must be an object"
    assert set(data.keys()) == EXPECTED_KEYS, (
        f"JSON response must contain exactly {EXPECTED_KEYS}; got {set(data.keys())}"
    )
    return data


def assert_number(value, name):
    assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{name} must be numeric"
    assert math.isfinite(value), f"{name} must be finite"


def check_original_result(data):
    expected_alpha = [22.5, 23.1, 22.8]
    expected_beta = [21.0, 20.8, 21.2]

    assert len(data["alpha_values"]) == len(expected_alpha), "Incorrect number of alpha values extracted."
    assert len(data["beta_values"]) == len(expected_beta), "Incorrect number of beta values extracted."
    for act, exp in zip(data["alpha_values"], expected_alpha):
        assert_number(act, "alpha value")
        assert math.isclose(act, exp, abs_tol=0.1), f"Alpha value {act} does not match expected {exp}"
    for act, exp in zip(data["beta_values"], expected_beta):
        assert_number(act, "beta value")
        assert math.isclose(act, exp, abs_tol=0.1), f"Beta value {act} does not match expected {exp}"

    for key in EXPECTED_KEYS - {"alpha_values", "beta_values"}:
        assert_number(data[key], key)
    assert math.isclose(data["t_test_p_value"], 0.003, abs_tol=0.005), \
        f"t_test_p_value {data['t_test_p_value']} is not close to expected 0.003"
    assert math.isclose(data["bayesian_posterior_mean"], 22.763, abs_tol=0.01), \
        f"bayesian_posterior_mean {data['bayesian_posterior_mean']} is not close to expected 22.763"
    assert math.isclose(data["bayesian_ci_lower"], 21.639, abs_tol=0.05), \
        f"bayesian_ci_lower {data['bayesian_ci_lower']} is not close to expected 21.639"
    assert math.isclose(data["bayesian_ci_upper"], 23.887, abs_tol=0.05), \
        f"bayesian_ci_upper {data['bayesian_ci_upper']} is not close to expected 23.887"


def betacf(a, b, x):
    qab = a + b
    qap = a + 1.0
    qam = a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < 3e-14:
        d = 3e-14
    d = 1.0 / d
    h = d
    for m in range(1, 301):
        m2 = 2 * m
        d = 1.0 + m * (b - m) * x / ((qam + m2) * (a + m2))
        if abs(d) < 3e-14:
            d = 3e-14
        c = 1.0 + m * (b - m) * x / ((qam + m2) * (a + m2)) / c
        if abs(c) < 3e-14:
            c = 3e-14
        d = 1.0 / d
        h *= d * c
        d = 1.0 - (a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        if abs(d) < 3e-14:
            d = 3e-14
        c = 1.0 - (a + m) * (qab + m) * x / ((a + m2) * (qap + m2)) / c
        if abs(c) < 3e-14:
            c = 3e-14
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < 3e-12:
            break
    return h


def regularized_beta(x, a, b):
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    bt = math.exp(math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
                  + a * math.log(x) + b * math.log1p(-x))
    if x < (a + 1.0) / (a + b + 2.0):
        return bt * betacf(a, b, x) / a
    return 1.0 - bt * betacf(b, a, 1.0 - x) / b


def welch_p_value(a, b):
    ma = sum(a) / len(a)
    mb = sum(b) / len(b)
    va = sum((x - ma) ** 2 for x in a) / (len(a) - 1)
    vb = sum((x - mb) ** 2 for x in b) / (len(b) - 1)
    sa = va / len(a)
    sb = vb / len(b)
    t = abs(ma - mb) / math.sqrt(sa + sb)
    df = (sa + sb) ** 2 / (sa * sa / (len(a) - 1) + sb * sb / (len(b) - 1))
    return regularized_beta(df / (df + t * t), df / 2.0, 0.5)


def expected_analysis(alpha, beta):
    p = welch_p_value(alpha, beta)
    precision = len(alpha) + 1.0 / 25.0
    posterior_variance = 1.0 / precision
    posterior_mean = (sum(alpha) + 20.0 / 25.0) / precision
    margin = 1.959963984540054 * math.sqrt(posterior_variance)
    return {
        "t_test_p_value": round(p, 3),
        "bayesian_posterior_mean": round(posterior_mean, 3),
        "bayesian_ci_lower": round(posterior_mean - margin, 3),
        "bayesian_ci_upper": round(posterior_mean + margin, 3),
    }


def listening_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as fh:
                next(fh)
                for line in fh:
                    fields = line.split()
                    if fields[3] == "0A" and int(fields[1].split(":")[1], 16) == 8080:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(entry)
        except (FileNotFoundError, PermissionError):
            continue
    return None


def capture_service(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as fh:
        argv = [part.decode(errors="surrogateescape") for part in fh.read().split(b"\0") if part]
    assert argv, "Could not determine the service command"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = {}
    with open(f"/proc/{pid}/environ", "rb") as fh:
        for item in fh.read().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    return argv, cwd, env


def stop_service():
    deadline = time.time() + 8
    while time.time() < deadline:
        pid = listening_pid()
        if pid is None:
            return
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            continue
        time.sleep(0.25)
        if listening_pid() == pid:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.25)
    pytest.fail("Could not stop the submitted service for the transformed-input test")


def restart_and_wait(argv, cwd, env):
    with open("/tmp/restarted_service.log", "ab", buffering=0) as log:
        subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                         stdout=log, stderr=log, start_new_session=True)
    deadline = time.time() + 90
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(URL, timeout=2)
            if response.status_code == 200:
                return
        except requests.exceptions.RequestException as exc:
            last_error = exc
        time.sleep(0.5)
    pytest.fail(f"Service did not restart after the audio input changed: {last_error}")


def make_random_audio():
    path = "/app/data/telemetry_audio.wav"
    audio = AudioSegment.from_wav(path)
    threshold = audio.dBFS - 14
    gaps = detect_silence(audio, min_silence_len=180, silence_thresh=threshold, seek_step=5)
    internal = [(start, end) for start, end in gaps if start > 50 and end < len(audio) - 50]
    assert len(internal) >= 5, "Could not identify the six spoken reading phrases in telemetry_audio.wav"
    chosen = sorted(sorted(internal, key=lambda pair: pair[1] - pair[0], reverse=True)[:5])
    boundaries = [(start + end) // 2 for start, end in chosen]
    chunks = []
    start = 0
    for boundary in boundaries:
        chunks.append(audio[start:boundary])
        start = boundary
    chunks.append(audio[start:])
    assert len(chunks) == 6

    alpha_source = [22.5, 23.1, 22.8]
    beta_source = [21.0, 20.8, 21.2]
    for _ in range(100):
        count = 4 + secrets.randbelow(3)
        alpha_indices = [secrets.randbelow(3) for _ in range(count)]
        beta_indices = [secrets.randbelow(3) for _ in range(count)]
        alpha = [alpha_source[i] for i in alpha_indices]
        beta = [beta_source[i] for i in beta_indices]
        stats = expected_analysis(alpha, beta)
        if (len(set(alpha)) >= 2 and len(set(beta)) >= 2
                and stats["bayesian_posterior_mean"] != 22.763
                and stats["t_test_p_value"] != 0.003):
            break
    else:
        pytest.fail("Could not construct a distinct transformed telemetry input")

    transformed = AudioSegment.silent(duration=100, frame_rate=audio.frame_rate)
    for ai, bi in zip(alpha_indices, beta_indices):
        transformed += chunks[2 * ai]
        transformed += AudioSegment.silent(duration=180, frame_rate=audio.frame_rate)
        transformed += chunks[2 * bi + 1]
        transformed += AudioSegment.silent(duration=260, frame_rate=audio.frame_rate)
    transformed.export(path, format="wav")
    return alpha, beta, stats


def check_dynamic_result(data, alpha, beta, stats):
    assert data["alpha_values"] == [round(x, 3) for x in alpha], (
        f"alpha_values were not transcribed from the transformed audio: {data['alpha_values']}"
    )
    assert data["beta_values"] == [round(x, 3) for x in beta], (
        f"beta_values were not transcribed from the transformed audio: {data['beta_values']}"
    )
    for key, expected in stats.items():
        assert_number(data[key], key)
        assert math.isclose(data[key], expected, abs_tol=5e-7), (
            f"{key} was {data[key]}, expected the correctly rounded value {expected}"
        )


def test_pipeline_against_original_and_transformed_audio():
    initial = get_metrics()
    check_original_result(initial)

    pid = listening_pid()
    assert pid is not None, "No process was found listening on port 8080"
    argv, cwd, env = capture_service(pid)
    alpha, beta, stats = make_random_audio()
    stop_service()
    restart_and_wait(argv, cwd, env)
    dynamic = get_metrics()
    check_dynamic_result(dynamic, alpha, beta, stats)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
