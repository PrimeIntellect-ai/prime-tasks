#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import socket
import stat
import subprocess
import pytest

HOST = "127.0.0.1"
PORT = 8080
SIM_DIR = "/home/user/sim_env"
FLOAT_RE = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")
EXPECTED_BINS = [
    "0-10", "10-20", "20-30", "30-40", "40-50",
    "50-60", "60-70", "70-80", "80-90", "90-100"
]


def send_request(payload: str) -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        try:
            s.connect((HOST, PORT))
        except ConnectionRefusedError:
            pytest.fail(f"Could not connect to {HOST}:{PORT}. Is the server running?")

        s.sendall(payload.encode('utf-8'))

        response = b""
        while True:
            try:
                data = s.recv(4096)
                if not data:
                    break
                response += data
            except socket.timeout:
                break
    return response.decode('utf-8').strip()


def read_coefficients():
    result = subprocess.run(
        ["tesseract", "/app/system_params.png", "stdout"],
        text=True, capture_output=True, timeout=15, check=True
    )
    match = re.search(
        r"COEFFICIENTS\s*:\s*ALPHA\s*=\s*([-+0-9.eE]+)\s+BETA\s*=\s*([-+0-9.eE]+)",
        result.stdout,
        re.IGNORECASE,
    )
    assert match, f"Could not read coefficients from image OCR output: {result.stdout!r}"
    return float(match.group(1)), float(match.group(2))


def trapezoidal_expected(x, alpha, beta, n=1000):
    h = x / n
    total = 0.5 * ((alpha * 0.0 ** 2 + beta * 0.0) +
                   (alpha * x ** 2 + beta * x))
    for i in range(1, n):
        xi = i * h
        total += alpha * xi ** 2 + beta * xi
    return total * h


def parse_single_float(response):
    text = response.strip()
    assert FLOAT_RE.fullmatch(text), f"Expected only one float, got {response!r}"
    value = float(text)
    assert math.isfinite(value), f"Expected a finite float, got {response!r}"
    return value


def parse_histogram(response):
    lines = response.strip().split('\n')
    assert len(lines) == 10, f"Expected 10 histogram lines, got {len(lines)}:\n{response}"
    counts = []
    for i, line in enumerate(lines):
        match = re.fullmatch(r"(\d+-\d+):\s*(\d+)", line.strip())
        assert match, f"Invalid histogram line {i + 1}: {line!r}"
        label, count = match.groups()
        assert label == EXPECTED_BINS[i], f"Expected bin {EXPECTED_BINS[i]}, got {label}"
        counts.append(int(count))
    assert sum(counts) == 5000, f"Expected sum of counts to be exactly 5000, got {sum(counts)}"
    return counts


def test_required_artifacts_exist():
    assert os.path.isdir(SIM_DIR), f"Missing required directory {SIM_DIR}"
    for name in ("integrate.sh", "density.sh", "server.sh"):
        path = os.path.join(SIM_DIR, name)
        info = os.stat(path)
        assert stat.S_ISREG(info.st_mode), f"{path} is not a regular file"
        assert os.access(path, os.R_OK), f"{path} is not readable"
        assert os.path.getsize(path) > 0, f"{path} is empty"


def test_integrate_accuracy():
    """Test that the INTEGRATE command returns the correct numerical result."""
    response = send_request("INTEGRATE 4.0\n")
    assert response, "No response received for INTEGRATE request."

    try:
        val = float(response)
    except ValueError:
        pytest.fail(f"Could not parse response as float: {response!r}")

    expected = 84.2666
    assert abs(val - expected) < 0.05, f"Integration result {val} is not within 0.05 of expected {expected}."


def test_direct_integrate_on_unpredictable_inputs():
    alpha, beta = read_coefficients()
    script = os.path.join(SIM_DIR, "integrate.sh")
    rng = secrets.SystemRandom()
    for _ in range(5):
        x = rng.uniform(0.35, 11.75)
        result = subprocess.run(
            ["bash", script, f"{x:.8f}"],
            text=True, capture_output=True, timeout=15, check=True
        )
        value = parse_single_float(result.stdout)
        expected = trapezoidal_expected(float(f"{x:.8f}"), alpha, beta)
        assert abs(value - expected) < 0.02, (
            f"integrate.sh returned {value} for X={x:.8f}; expected {expected}"
        )


def test_server_integrates_unpredictable_inputs_over_multiple_connections():
    alpha, beta = read_coefficients()
    rng = secrets.SystemRandom()
    for _ in range(4):
        x_text = f"{rng.uniform(0.4, 11.5):.7f}"
        response = send_request(f"INTEGRATE {x_text}\n")
        value = parse_single_float(response)
        expected = trapezoidal_expected(float(x_text), alpha, beta)
        assert abs(value - expected) < 0.02, (
            f"Server returned {value} for X={x_text}; expected {expected}"
        )


def test_density_formatting():
    """Test that the DENSITY command returns the correctly formatted histogram."""
    response = send_request("DENSITY\n")
    assert response, "No response received for DENSITY request."

    lines = response.strip().split('\n')
    assert len(lines) == 10, f"Expected 10 lines in DENSITY response, got {len(lines)}:\n{response}"

    expected_bins = [
        "0-10", "10-20", "20-30", "30-40", "40-50",
        "50-60", "60-70", "70-80", "80-90", "90-100"
    ]

    total_count = 0
    for i, line in enumerate(lines):
        match = re.match(r"^(\d+-\d+):\s*(\d+)$", line.strip())
        assert match, f"Line {i+1} does not match expected format '[bin_start]-[bin_end]: <count>': {line!r}"
        bin_label, count_str = match.groups()
        assert bin_label == expected_bins[i], f"Expected bin {expected_bins[i]}, got {bin_label}"
        total_count += int(count_str)

    assert total_count == 5000, f"Expected sum of counts to be exactly 5000, got {total_count}"


def test_density_is_generated_and_approximately_uniform():
    script = os.path.join(SIM_DIR, "density.sh")
    direct = subprocess.run(
        ["bash", script], text=True, capture_output=True, timeout=20, check=True
    ).stdout.strip()
    responses = [direct, send_request("DENSITY\n"), send_request("DENSITY\n")]
    histograms = [parse_histogram(response) for response in responses]

    assert len({tuple(counts) for counts in histograms}) > 1, (
        "Repeated density runs returned identical histograms; output appears canned"
    )

    expected = 500.0
    for counts in histograms:
        chi_square = sum((count - expected) ** 2 / expected for count in counts)
        assert chi_square < 60.0, (
            f"Histogram is not consistent with 5000 uniform samples: {counts} "
            f"(chi-square={chi_square:.3f})"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
