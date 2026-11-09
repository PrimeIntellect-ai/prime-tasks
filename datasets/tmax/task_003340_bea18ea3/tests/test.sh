#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
from pathlib import Path

import numpy as np
import pytest
import requests

API_URL = "http://127.0.0.1:8000/process"


def kernel_from_image():
    proc = subprocess.run(
        ["tesseract", "/app/kernel.png", "stdout", "--psm", "6"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert proc.returncode == 0, f"Tesseract failed: {proc.stderr}"
    values = re.findall(r"[-+]?\d+(?:\.\d+)?", proc.stdout)
    assert len(values) == 9, f"Could not extract a 3x3 kernel from image; OCR output: {proc.stdout!r}"
    return np.asarray([float(v) for v in values], dtype=np.float64).reshape(3, 3)


def expected_filter(input_data, kernel):
    height, width = input_data.shape
    expected = np.zeros((height, width), dtype=np.float64)
    for y in range(height):
        for x in range(width):
            total = 0.0
            for ky in range(3):
                for kx in range(3):
                    iy = y + ky - 1
                    ix = x + kx - 1
                    if 0 <= iy < height and 0 <= ix < width:
                        total += input_data[iy, ix] * kernel[ky, kx]
            expected[y, x] = total
    return expected


def listening_pids():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            host_port = fields[1]
            if ":" not in host_port:
                continue
            host, port = host_port.rsplit(":", 1)
            if int(port, 16) != 8000:
                continue
            # The task requires the IPv4 loopback listener specifically.
            if table.endswith("tcp") and host != "0100007F":
                continue
            socket_inodes.add(fields[9])

    pids = set()
    for proc_dir in Path("/proc").iterdir():
        if not proc_dir.name.isdigit():
            continue
        fd_dir = proc_dir / "fd"
        try:
            fds = list(fd_dir.iterdir())
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in socket_inodes:
                pids.add(int(proc_dir.name))
                break
    return pids


def test_server_loaded_filter_through_ctypes():
    pids = listening_pids()
    assert pids, "No process is listening on 127.0.0.1:8000"

    matching = []
    for pid in pids:
        try:
            maps = Path(f"/proc/{pid}/maps").read_text()
        except OSError:
            continue
        if "/home/user/libfilter.so" in maps and "_ctypes" in maps:
            matching.append(pid)

    assert matching, (
        "The API process must load /home/user/libfilter.so through Python ctypes; "
        f"listener PIDs were {sorted(pids)}"
    )


def test_api_on_runtime_random_inputs():
    kernel = kernel_from_image()
    rng = np.random.default_rng(secrets.randbits(128))

    dimensions = set()
    while len(dimensions) < 4:
        dimensions.add((int(rng.integers(31, 68)), int(rng.integers(29, 66))))

    for width, height in dimensions:
        input_data = rng.random((height, width), dtype=np.float64)
        expected = expected_filter(input_data, kernel).reshape(-1)
        payload = {
            "width": width,
            "height": height,
            "data": input_data.reshape(-1).tolist(),
        }

        try:
            response = requests.post(API_URL, json=payload, timeout=10)
        except requests.exceptions.RequestException as exc:
            pytest.fail(f"Failed to connect to API: {exc}")

        assert response.status_code == 200, (
            f"Expected status code 200 for {width}x{height}, got {response.status_code}"
        )
        try:
            body = response.json()
        except (ValueError, json.JSONDecodeError) as exc:
            pytest.fail(f"Failed to decode JSON response: {exc}")

        assert isinstance(body, dict) and "result" in body, "Response JSON missing 'result' key"
        try:
            output = np.asarray(body["result"], dtype=np.float64)
        except (TypeError, ValueError) as exc:
            pytest.fail(f"Result is not a numeric list: {exc}")

        assert output.shape == (width * height,), (
            f"Expected output shape ({width * height},), got {output.shape}"
        )
        assert np.all(np.isfinite(output)), "Output contains non-finite values"
        mse = np.mean((expected - output) ** 2)
        assert mse < 0.05, f"MSE {mse} is not less than 0.05 for {width}x{height}"


def test_required_unit_test_script_exists_and_runs():
    test_path = Path("/home/user/test_api.py")
    assert test_path.is_file(), "/home/user/test_api.py does not exist"
    assert test_path.stat().st_size > 0, "/home/user/test_api.py is empty"
    proc = subprocess.run(
        ["python3", str(test_path)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=45,
    )
    assert proc.returncode == 0, f"/home/user/test_api.py failed:\n{proc.stdout}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
