#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import subprocess

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"


def read_model_parameters():
    text = subprocess.check_output(
        ["tesseract", "/app/system_model.png", "stdout"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    values = {}
    for name in ("mu", "sigma", "threshold"):
        match = re.search(rf"\b{name}\s*=\s*(-?\d+(?:\.\d+)?)", text, re.IGNORECASE)
        assert match, f"Could not derive {name} from system_model.png; OCR output was {text!r}"
        values[name] = float(match.group(1))
    return values


def get_json(path, timeout=5):
    url = f"{BASE_URL}{path}"
    try:
        response = requests.get(url, timeout=timeout)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {url}: {e}")
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        return response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON. Response: {response.text}")


def test_montecarlo_endpoint():
    url = f"{BASE_URL}/montecarlo?samples=1000000"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON. Response: {response.text}")

    assert "mc_prob" in data, f"Key 'mc_prob' missing in response. Got: {data}"

    mc_prob = data["mc_prob"]
    assert isinstance(mc_prob, (int, float)), f"'mc_prob' must be a number, got {type(mc_prob)}"

    expected_prob = 0.02275
    tolerance = 0.005
    assert abs(mc_prob - expected_prob) <= tolerance, f"Expected 'mc_prob' to be around {expected_prob} (+/- {tolerance}), but got {mc_prob}"


def test_integrate_endpoint():
    url = f"{BASE_URL}/integrate"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON. Response: {response.text}")

    assert "exact_prob" in data, f"Key 'exact_prob' missing in response. Got: {data}"

    exact_prob = data["exact_prob"]
    assert isinstance(exact_prob, (int, float)), f"'exact_prob' must be a number, got {type(exact_prob)}"

    expected_exact_prob = math.erfc(2.0 / math.sqrt(2.0)) / 2.0
    tolerance = 0.0001

    assert abs(exact_prob - expected_exact_prob) <= tolerance, f"Expected 'exact_prob' to be around {expected_exact_prob} (+/- {tolerance}), but got {exact_prob}"


def test_test_endpoint():
    url = f"{BASE_URL}/test"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON. Response: {response.text}")

    assert "z_score" in data, f"Key 'z_score' missing in response. Got: {data}"

    z_score = data["z_score"]
    assert isinstance(z_score, (int, float)), f"'z_score' must be a number, got {type(z_score)}"

    expected_z_score = (126.5 - 120.0) / (30.0 / math.sqrt(100))
    tolerance = 0.001

    assert abs(z_score - expected_z_score) <= tolerance, f"Expected 'z_score' to be around {expected_z_score} (+/- {tolerance}), but got {z_score}"


def test_montecarlo_uses_requested_sample_counts():
    model = read_model_parameters()
    expected = math.erfc(
        (model["threshold"] - model["mu"]) / (model["sigma"] * math.sqrt(2.0))
    ) / 2.0

    rng = random.SystemRandom()
    sample_counts = set()
    while len(sample_counts) < 4:
        sample_counts.add(rng.randrange(20000, 50001))

    results = []
    for samples in sample_counts:
        data = get_json(f"/montecarlo?samples={samples}")
        assert "mc_prob" in data, f"Key 'mc_prob' missing in response. Got: {data}"
        value = data["mc_prob"]
        assert isinstance(value, (int, float)) and not isinstance(value, bool)
        assert math.isfinite(value) and 0.0 <= value <= 1.0

        # An empirical proportion from exactly N trials must be an integer divided by N.
        successes = value * samples
        assert abs(successes - round(successes)) <= 1e-6, (
            f"mc_prob={value} is not an empirical proportion for samples={samples}"
        )

        standard_error = math.sqrt(expected * (1.0 - expected) / samples)
        assert abs(value - expected) <= 7.0 * standard_error + 1.0 / samples, (
            f"Monte Carlo result {value} is inconsistent with OCR-derived model probability "
            f"{expected} for samples={samples}"
        )
        results.append(value)

    assert len(set(results)) > 1, "Repeated Monte Carlo requests returned a fixed value"


def test_test_endpoint_reads_current_csv():
    model = read_model_parameters()
    path = "/app/profiling_data.csv"
    with open(path, "rb") as f:
        original = f.read()

    rng = random.SystemRandom()
    n = rng.randrange(17, 42)
    target_mean = model["mu"] + rng.uniform(-18.0, 18.0)
    offsets = [rng.uniform(-25.0, 25.0) for _ in range(n)]
    correction = sum(offsets) / n
    values = [target_mean + offset - correction for offset in offsets]

    try:
        with open(path, "w") as f:
            for value in values:
                f.write(f"{value:.12f}\n")

        with open(path) as f:
            written_values = [float(line.strip()) for line in f if line.strip()]
        expected = ((sum(written_values) / len(written_values)) - model["mu"]) / (
            model["sigma"] / math.sqrt(len(written_values))
        )

        data = get_json("/test")
        assert "z_score" in data, f"Key 'z_score' missing in response. Got: {data}"
        value = data["z_score"]
        assert isinstance(value, (int, float)) and not isinstance(value, bool)
        assert math.isfinite(value)
        assert abs(value - expected) <= 1e-6, (
            f"Expected z_score {expected} from the current randomized CSV, got {value}"
        )
    finally:
        with open(path, "wb") as f:
            f.write(original)


def test_listener_is_a_go_executable():
    port_hex = f"{9090:04X}"
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_address = fields[1]
                    state = fields[3]
                    if local_address.rsplit(":", 1)[-1].upper() == port_hex and state == "0A":
                        socket_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    assert socket_inodes, "No process is listening on port 9090"
    listener_pids = set()
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
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in socket_inodes:
                    listener_pids.add(entry)
                    break
        except OSError:
            continue

    assert listener_pids, "Could not identify the process listening on port 9090"
    go_listener = False
    diagnostics = []
    for pid in listener_pids:
        exe = f"/proc/{pid}/exe"
        try:
            with open(exe, "rb") as f:
                assert f.read(4) == b"\x7fELF", f"Listener PID {pid} is not an ELF executable"
            result = subprocess.run(
                ["go", "version", "-m", exe],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=5,
            )
            diagnostics.append(result.stdout)
            if result.returncode == 0 and re.search(r"\bgo1\.\d+", result.stdout):
                go_listener = True
        except (OSError, subprocess.SubprocessError) as exc:
            diagnostics.append(str(exc))

    assert go_listener, "The port 9090 listener is not a Go executable: " + " | ".join(diagnostics)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
