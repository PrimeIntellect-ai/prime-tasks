#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import subprocess
import time

import pytest
import requests

SOURCE = "/home/user/mc_integral.c"
BINARY = "/home/user/mc_integral"
URL = "http://127.0.0.1:8080/simulate"


def read_coeff():
    text = subprocess.check_output(
        ["tesseract", "/app/config.png", "stdout"],
        text=True,
        stderr=subprocess.DEVNULL,
        timeout=15,
    )
    match = re.search(r"COEFF\s*=\s*([0-9]+(?:\.[0-9]+)?)", text, re.I)
    assert match, f"Could not OCR COEFF from config.png; OCR output was {text!r}"
    return float(match.group(1))


def expected_integral():
    coeff = read_coeff()
    return math.atan(1.0 / math.sqrt(coeff)) / math.sqrt(coeff)


def run_binary(samples, threads):
    completed = subprocess.run(
        [BINARY, str(samples), str(threads)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=True,
    )
    output = completed.stdout.strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", output), (
        f"Binary stdout must contain only one floating-point number, got {completed.stdout!r}"
    )
    value = float(output)
    assert math.isfinite(value)
    return value


def request_simulation(samples, threads, retries=5):
    for attempt in range(retries):
        try:
            return requests.get(
                URL,
                params={"samples": samples, "threads": threads},
                timeout=20,
            )
        except requests.RequestException:
            if attempt == retries - 1:
                pytest.fail("Failed to connect to the HTTP server at 127.0.0.1:8080")
            time.sleep(1)


def parse_response(response):
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    assert response.headers.get("Content-Type", "").lower().startswith("application/json"), (
        f"Expected application/json, got {response.headers.get('Content-Type')!r}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert "result" in data, "JSON response does not contain the 'result' key."
    result = data["result"]
    assert isinstance(result, (int, float)) and not isinstance(result, bool), (
        f"'result' must be a number, got {type(result)}"
    )
    assert math.isfinite(float(result))
    return float(result)


def test_c_source_exists():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."


def test_c_binary_exists_and_executable():
    assert os.path.isfile(BINARY), f"{BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    with open(BINARY, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable"


def test_source_and_binary_use_openmp():
    source = open(SOURCE, encoding="utf-8", errors="replace").read()
    assert re.search(r"#\s*include\s*<omp\.h>", source), "C source does not include omp.h"
    assert re.search(r"#\s*pragma\s+omp\s+parallel", source), "C source has no OpenMP parallel region"
    assert re.search(r"\bomp_set_num_threads\s*\(", source), "C source does not set the requested thread count"
    assert re.search(r"\b(rand_r|random_r|drand48_r|erand48|xorshift|pcg|rng|random)\b", source, re.I), (
        "C source does not show use of a per-thread/random sampling generator"
    )

    symbols = subprocess.check_output(["nm", "-D", BINARY], text=True, errors="replace")
    assert "omp_set_num_threads" in symbols, "Binary does not call omp_set_num_threads"
    assert re.search(r"GOMP_parallel|GOMP_parallel_loop", symbols), "Binary is not linked with an OpenMP parallel region"


def test_compiled_estimator_on_multiple_arguments():
    expected = expected_integral()
    cases = [(800003, 1), (1100003, 3), (1400009, 4)]
    values = [run_binary(samples, threads) for samples, threads in cases]
    for case, value in zip(cases, values):
        assert abs(value - expected) <= 0.30, (
            f"Binary estimate {value} for samples={case[0]}, threads={case[1]} "
            f"is too far from analytical value {expected}"
        )
    assert max(values) - min(values) > 1e-7, (
        "Estimator returned the same constant for different sample and thread arguments"
    )


def test_http_server_response():
    # Preserve the original fixed request and accuracy assertion.
    response = request_simulation(5000000, 4)
    result = parse_response(response)
    assert 30.3 <= result <= 30.5, (
        f"Estimated integral {result} is out of expected bounds [30.3, 30.5]."
    )

    # Also exercise a runtime-selected argument pair and derive its answer from config.png.
    samples = secrets.choice([650011, 725009, 900001, 1050011])
    threads = secrets.choice([1, 2, 3, 4])
    result = parse_response(request_simulation(samples, threads))
    expected = expected_integral()
    assert abs(result - expected) <= 0.38, (
        f"HTTP estimate {result} for samples={samples}, threads={threads} "
        f"is too far from analytical value {expected}"
    )


def test_z_server_executes_binary_and_forwards_arguments():
    # Atomically substitute a one-shot probe. A constant-response server cannot know
    # the random probe value, and the log verifies both command-line arguments.
    samples = secrets.randbelow(800000) + 120000
    threads = secrets.randbelow(7) + 1
    probe_value = 500.0 + secrets.randbelow(1000000) / 1000.0
    nonce = secrets.token_hex(12)
    log_path = f"/tmp/mc_probe_{nonce}.log"
    backup = f"{BINARY}.verifier_backup_{nonce}"
    probe = f"{BINARY}.verifier_probe_{nonce}"

    script = (
        "#!/bin/sh\n"
        f"printf '%s %s\\n' \"$1\" \"$2\" > {log_path!r}\n"
        f"printf '%.12f\\n' {probe_value!r}\n"
    )
    with open(probe, "w", encoding="utf-8") as handle:
        handle.write(script)
    os.chmod(probe, 0o755)

    os.replace(BINARY, backup)
    os.replace(probe, BINARY)
    try:
        result = parse_response(request_simulation(samples, threads, retries=3))
        assert result == pytest.approx(probe_value, rel=0, abs=1e-9), (
            "HTTP server did not return the output of /home/user/mc_integral"
        )
        assert os.path.isfile(log_path), "Probe executable was not invoked by the HTTP server"
        with open(log_path, encoding="utf-8") as handle:
            invocation = handle.read().strip()
        assert invocation == f"{samples} {threads}", (
            f"Server did not forward query arguments correctly; probe received {invocation!r}"
        )
    finally:
        if os.path.exists(BINARY):
            os.unlink(BINARY)
        os.replace(backup, BINARY)
        if os.path.exists(probe):
            os.unlink(probe)
        if os.path.exists(log_path):
            os.unlink(log_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
