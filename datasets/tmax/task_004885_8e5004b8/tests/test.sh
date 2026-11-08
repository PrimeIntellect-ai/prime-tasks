#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import json
import os
import socket
import subprocess
import time
import urllib.parse
import urllib.request

import numpy as np
from PIL import Image
import psutil


def wait_for_server(port, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                return True
        except OSError:
            time.sleep(0.2)
    return False


def golden_signature(image_path):
    pixels = np.asarray(Image.open(image_path).convert("L"), dtype=np.float64)
    grad_y, grad_x = np.gradient(pixels)
    gradient_magnitude = np.hypot(grad_x, grad_y)
    singular_values = np.linalg.svd(
        gradient_magnitude, compute_uv=False, full_matrices=False
    )
    return np.asarray(singular_values[:10], dtype=np.float64)


def make_request(image_path):
    url = "http://127.0.0.1:8080/?" + urllib.parse.urlencode({"image": image_path})
    try:
        request = urllib.request.Request(url, data=b"", method="POST")
        with urllib.request.urlopen(request, timeout=15) as response:
            if response.status != 200:
                return None
            value = json.loads(response.read().decode("utf-8"))
        if isinstance(value, dict) and "signature" in value:
            return value["signature"]
        if isinstance(value, list):
            return value
        if isinstance(value, str) and value.startswith("["):
            return json.loads(value)
    except Exception:
        return None
    return None


def total_rss_mb(process):
    processes = [process]
    try:
        processes.extend(process.children(recursive=True))
    except (psutil.NoSuchProcess, psutil.AccessDenied):
        pass

    total = 0
    for item in processes:
        try:
            total += item.memory_info().rss
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    return total / (1024 * 1024)


def checked_array(result, expected_shape=(10,)):
    assert result is not None, "A request failed or returned invalid JSON."
    array = np.asarray(result, dtype=np.float64)
    assert array.shape == expected_shape, f"Invalid signature shape: {array.shape}"
    assert np.all(np.isfinite(array)), "Signature contains NaN or infinity."
    return array


def test_service_memory_and_race_condition():
    service_path = "/home/user/image_service.py"
    assert os.path.exists(service_path), f"Service script not found at {service_path}"
    assert os.path.isfile(service_path), f"Service path is not a file: {service_path}"

    # This unpredictable image prevents a fabricated constant response from passing.
    challenge_path = "/tmp/verifier_challenge.png"
    rng = np.random.default_rng()
    challenge_pixels = rng.integers(0, 256, size=(100, 100, 3), dtype=np.uint8)
    Image.fromarray(challenge_pixels, mode="RGB").save(challenge_path)

    reference_path = "/app/reference_sample.png"
    expected_reference = golden_signature(reference_path)
    expected_challenge = golden_signature(challenge_path)

    process = subprocess.Popen(
        ["python3", service_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        assert wait_for_server(8080, timeout=15), \
            "Server did not start on port 8080 within timeout."
        ps_process = psutil.Process(process.pid)

        num_requests = 500
        peak_memory = total_rss_mb(ps_process)
        with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
            futures = [
                executor.submit(make_request, reference_path)
                for _ in range(num_requests)
            ]
            while any(not future.done() for future in futures):
                assert process.poll() is None, "Service exited during the load test."
                peak_memory = max(peak_memory, total_rss_mb(ps_process))
                time.sleep(0.05)
            results = [future.result() for future in futures]

        peak_memory = max(peak_memory, total_rss_mb(ps_process))
        assert peak_memory <= 150.0, \
            f"PEAK_MEM_MB exceeded threshold: {peak_memory:.2f} MB > 150.0 MB. Memory leak not fixed."

        valid_results = [result for result in results if result is not None]
        assert len(valid_results) > 0, "No valid signatures returned by the service."
        assert len(valid_results) == num_requests, \
            f"Only {len(valid_results)} of {num_requests} requests returned valid signatures."

        arrays = [checked_array(result) for result in valid_results]
        reference = arrays[0]
        max_mse = 0.0
        for array in arrays[1:]:
            if array.shape != reference.shape:
                max_mse = float("inf")
                break
            mse = float(np.mean((array - reference) ** 2))
            if mse > max_mse:
                max_mse = mse
        assert max_mse <= 1e-5, \
            f"SIGNATURE_MSE exceeded threshold: {max_mse} > 1e-5. Race condition in math operations not fixed."

        for array in arrays:
            mse = float(np.mean((array - expected_reference) ** 2))
            assert mse <= 1e-5, \
                f"Reference signature differs from the independently computed golden signature: MSE={mse}"

        # Exercise the implementation on an image unknown while the agent was editing.
        challenge_results = [make_request(challenge_path) for _ in range(3)]
        challenge_arrays = [checked_array(result) for result in challenge_results]
        for array in challenge_arrays:
            mse = float(np.mean((array - expected_challenge) ** 2))
            assert mse <= 1e-5, \
                f"Challenge signature differs from the independently computed golden signature: MSE={mse}"

    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
