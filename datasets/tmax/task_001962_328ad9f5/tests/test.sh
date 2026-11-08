#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import struct
import subprocess
import time
import urllib.error
import urllib.request

import numpy as np
import pytest
from scipy.io import wavfile


def run_python(code):
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = ":".join([
        "/app/cpp_core",
        "/app/c_filter",
        "/app/wav_parser/target/release",
        env.get("LD_LIBRARY_PATH", ""),
    ])
    return subprocess.run(
        ["python3", "-c", code], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )


def test_compiled_libraries_exist_and_work():
    filter_lib = "/app/c_filter/libfilter.so"
    core_lib = "/app/cpp_core/libcore.so"
    rust_lib = "/app/wav_parser/target/release/libwav_parser.so"

    assert os.path.exists(filter_lib), "Missing libfilter.so"
    assert os.path.exists(core_lib), "Missing libcore.so"
    assert os.path.exists(rust_lib), "Missing compiled libwav_parser.so"
    assert os.path.exists("/app/run_server.sh"), "Missing /app/run_server.sh"

    # Load and exercise the C filter rather than accepting a placeholder file.
    filter_check = run_python(r'''
import ctypes
import numpy as np
lib = ctypes.CDLL("/app/c_filter/libfilter.so")
fn = lib.moving_average
fn.argtypes = [ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_float), ctypes.c_size_t, ctypes.c_size_t]
fn.restype = None
x = np.array([1.0, 2.0, 4.0, 8.0, 16.0, -2.0], dtype=np.float32)
out = np.empty_like(x)
fn(x.ctypes.data_as(ctypes.POINTER(ctypes.c_float)), out.ctypes.data_as(ctypes.POINTER(ctypes.c_float)), x.size, 3)
expected = np.array([1.0, 1.5, 7.0/3.0, 14.0/3.0, 28.0/3.0, 22.0/3.0], dtype=np.float32)
assert np.allclose(out, expected, rtol=1e-6, atol=1e-6), (out, expected)
''')
    assert filter_check.returncode == 0, filter_check.stderr

    # Load and exercise the Rust WAV parser on a header whose values differ
    # from the fixture defaults, catching hard-coded or dangling results.
    rust_check = run_python(r'''
import ctypes, struct
class Header(ctypes.Structure):
    _fields_ = [("channels", ctypes.c_uint16), ("sample_rate", ctypes.c_uint32)]
lib = ctypes.CDLL("/app/wav_parser/target/release/libwav_parser.so")
fn = lib.parse_header
fn.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]
fn.restype = ctypes.POINTER(Header)
channels, rate, bits = 2, 44100, 16
block = channels * bits // 8
header = (b"RIFF" + struct.pack("<I", 36) + b"WAVEfmt " +
          struct.pack("<IHHIIHH", 16, 1, channels, rate, rate * block, block, bits) +
          b"data" + struct.pack("<I", 0))
buf = (ctypes.c_uint8 * len(header)).from_buffer_copy(header)
p = fn(buf, len(header))
assert bool(p), "parse_header returned NULL"
assert p.contents.channels == channels, p.contents.channels
assert p.contents.sample_rate == rate, p.contents.sample_rate
''')
    assert rust_check.returncode == 0, rust_check.stderr

    # libcore must be a loadable shared object and actually link the two FFI
    # components it is required to integrate.
    core_check = run_python('import ctypes; ctypes.CDLL("/app/cpp_core/libcore.so")')
    assert core_check.returncode == 0, core_check.stderr
    dynamic = subprocess.check_output(["readelf", "-d", core_lib], text=True)
    assert "libfilter.so" in dynamic, "libcore.so is not linked to libfilter.so"
    assert "libwav_parser.so" in dynamic, "libcore.so is not linked to libwav_parser.so"


def descendants(root_pid):
    result = {root_pid}
    changed = True
    while changed:
        changed = False
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            try:
                with open(f"/proc/{name}/status", "r") as f:
                    lines = f.read().splitlines()
                ppid = int(next(x for x in lines if x.startswith("PPid:")).split()[1])
                pid = int(name)
                if ppid in result and pid not in result:
                    result.add(pid)
                    changed = True
            except (OSError, StopIteration, ValueError):
                pass
    return result


def mapped_server_libraries(server_pid):
    mapped = set()
    for pid in descendants(server_pid):
        try:
            with open(f"/proc/{pid}/maps", "r") as f:
                text = f.read()
        except OSError:
            continue
        for library in ("libcore.so", "libfilter.so", "libwav_parser.so"):
            if library in text:
                mapped.add(library)
    return mapped


def extract_audio(body):
    data = json.loads(body)
    if isinstance(data, dict):
        for value in data.values():
            if isinstance(value, list):
                data = value
                break
    assert isinstance(data, list), "Expected API to return a JSON array of processed audio"
    assert len(data) > 0, "Returned audio array is empty"
    return data


def expected_moving_average(samples, window=1000):
    x = np.asarray(samples, dtype=np.float64)
    cumulative = np.empty(x.size + 1, dtype=np.float64)
    cumulative[0] = 0.0
    np.cumsum(x, out=cumulative[1:])
    starts = np.maximum(np.arange(x.size) + 1 - window, 0)
    sums = cumulative[1:] - cumulative[starts]
    counts = np.minimum(np.arange(x.size) + 1, window)
    return sums / counts


def test_server_metrics_correctness_and_rate_limiting():
    os.chmod("/app/run_server.sh", 0o755)
    server_proc = subprocess.Popen(["bash", "/app/run_server.sh"])

    server_up = False
    for _ in range(30):
        try:
            urllib.request.urlopen("http://127.0.0.1:8000/", timeout=1)
            server_up = True
            break
        except urllib.error.HTTPError:
            server_up = True
            break
        except Exception:
            time.sleep(0.5)
    assert server_up, "Server did not start on port 8000"
    time.sleep(0.5)

    try:
        url = "http://127.0.0.1:8000/process"
        payload = json.dumps({"file_path": "/app/fixture_audio.wav"}).encode("utf-8")
        headers = {"Content-Type": "application/json"}
        latencies = []
        status_codes = []
        first_body = None

        for i in range(6):
            req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
            start = time.time()
            try:
                with urllib.request.urlopen(req, timeout=15) as response:
                    latencies.append(time.time() - start)
                    status_codes.append(response.getcode())
                    if i == 0:
                        first_body = response.read().decode("utf-8")
            except urllib.error.HTTPError as e:
                latencies.append(time.time() - start)
                status_codes.append(e.code)
            except Exception as e:
                pytest.fail(f"Request failed: {e}")

        assert len(status_codes) == 6, "Did not complete 6 requests"
        assert status_codes[:5] == [200] * 5, f"First five requests must succeed: {status_codes}"
        assert status_codes[5] == 429, f"Expected HTTP 429 Too Many Requests on the 6th request, got {status_codes[5]}"
        assert latencies[0] <= 0.20, f"Latency metric failed: {latencies[0]:.3f}s > threshold 0.20s"

        returned = np.asarray(extract_audio(first_body), dtype=np.float64)
        sample_rate, samples = wavfile.read("/app/fixture_audio.wav")
        assert sample_rate == 8000
        expected = expected_moving_average(samples, 1000)
        assert returned.ndim == 1, f"Processed audio must be one-dimensional, got {returned.shape}"
        assert returned.size == expected.size, f"Expected {expected.size} output samples, got {returned.size}"
        assert np.all(np.isfinite(returned)), "Output contains non-finite values"
        mse = float(np.mean((returned - expected) ** 2))
        assert mse <= 1e-8, f"Moving-average output MSE too high: {mse}"

        mapped = mapped_server_libraries(server_proc.pid)
        required = {"libcore.so", "libfilter.so", "libwav_parser.so"}
        assert required <= mapped, f"Server did not load the required native pipeline libraries; mapped: {mapped}"
    finally:
        server_proc.terminate()
        try:
            server_proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server_proc.kill()
            server_proc.wait(timeout=5)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
