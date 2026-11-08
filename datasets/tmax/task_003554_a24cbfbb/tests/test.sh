#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import os
import re
import subprocess
import time
import urllib.error
import urllib.request

import pytest

BASE_URL = "http://127.0.0.1:8080"
START_PROCESS = None


def crc32c(data):
    crc = 0xFFFFFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (0x82F63B78 if crc & 1 else 0)
    return (~crc) & 0xFFFFFFFF


def post_checksum(data, timeout=15):
    req = urllib.request.Request(BASE_URL + "/checksum", data=data, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as response:
        body = response.read().decode("utf-8").strip()
        return response.status, response.headers, body


def uncommented(path):
    lines = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            lines.append(line.split("#", 1)[0])
    return "\n".join(lines)


def setup_module(module):
    global START_PROCESS
    assert os.path.isfile("/app/start.sh"), "/app/start.sh is missing"
    assert os.path.isfile("/app/server.cpp"), "/app/server.cpp is missing"
    assert os.path.isfile("/app/nginx.conf"), "/app/nginx.conf is missing"

    subprocess.run(["pkill", "-f", "/app/server"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["nginx", "-s", "stop"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)

    START_PROCESS = subprocess.Popen(
        ["bash", "/app/start.sh"],
        cwd="/app",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    deadline = time.time() + 25
    while time.time() < deadline:
        try:
            req = urllib.request.Request(BASE_URL + "/checksum", method="GET")
            urllib.request.urlopen(req, timeout=1)
        except urllib.error.HTTPError as e:
            if e.code == 405:
                return
        except (urllib.error.URLError, TimeoutError):
            pass

        if START_PROCESS.poll() not in (None, 0):
            pytest.fail(f"/app/start.sh exited with status {START_PROCESS.returncode}")
        time.sleep(0.2)
    pytest.fail("Service did not become ready after running /app/start.sh")


def test_build_and_dynamic_link_artifacts():
    makefile = "/app/libfastcrc-1.2/Makefile"
    library = "/app/libfastcrc-1.2/libfastcrc.so"
    server = "/app/server"

    assert os.path.isfile(makefile), "Library Makefile is missing"
    make_text = uncommented(makefile)
    assert re.search(r"(?:^|\s)-O3(?:\s|$)", make_text), "Makefile does not enable -O3"
    assert re.search(r"(?:^|\s)-fPIC(?:\s|$)", make_text), "Makefile does not compile position-independent code"
    assert re.search(r"(?:^|\s)-shared(?:\s|$)", make_text), "Makefile does not build a shared library"

    assert os.path.isfile(library), "libfastcrc.so was not built"
    assert os.path.isfile(server) and os.access(server, os.X_OK), "Compiled /app/server executable is missing"

    lib_info = subprocess.run(["readelf", "-h", library], text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True).stdout
    assert re.search(r"Type:\s+DYN", lib_info), "libfastcrc.so is not an ELF shared object"

    exports = subprocess.run(["nm", "-D", library], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True).stdout
    assert re.search(r"\b[TW]\s+compute_crc32c$", exports, re.MULTILINE), \
        "libfastcrc.so does not export compute_crc32c"

    undefined = subprocess.run(["nm", "-D", server], text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True).stdout
    assert re.search(r"\bU\s+compute_crc32c(?:@\S+)?$", undefined, re.MULTILINE), \
        "The server is not dynamically linked against compute_crc32c"

    linked = subprocess.run(["ldd", server], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True).stdout
    assert re.search(r"libfastcrc\.so\s+=>\s+\S+", linked), "ldd cannot resolve libfastcrc.so"
    assert "not found" not in linked, f"Server has unresolved shared libraries:\n{linked}"


def test_nginx_configuration():
    config = uncommented("/app/nginx.conf")
    assert re.search(r"\blisten\s+0\.0\.0\.0:8080\s*;", config), \
        "Nginx must listen on 0.0.0.0:8080"
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:9000\s*;", config), \
        "Nginx must proxy to 127.0.0.1:9000"
    assert re.search(r"\bclient_max_body_size\s+5M\s*;", config, re.IGNORECASE), \
        "client_max_body_size must be exactly 5M"

    zone_directives = re.findall(r"\blimit_req_zone\b[^;]*;", config)
    matching_zones = [d for d in zone_directives
                      if re.search(r"\bzone=req_limit_per_ip:10m\b", d, re.IGNORECASE)]
    assert matching_zones, "Missing req_limit_per_ip rate-limit zone with size 10m"
    assert all(re.search(r"\brate=100r/s\b", d, re.IGNORECASE) for d in matching_zones), \
        "req_limit_per_ip must have a rate of exactly 100 requests per second"
    assert re.search(r"\blimit_req\s+zone=req_limit_per_ip(?:\s+[^;]*)?;", config), \
        "The req_limit_per_ip zone is not applied with limit_req"

    checked = subprocess.run(["nginx", "-t", "-c", "/app/nginx.conf"], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert checked.returncode == 0, f"Invalid Nginx configuration:\n{checked.stdout}"


def test_correctness():
    """Preserve the known checksum test and verify runtime-derived test vectors."""
    data = b"hello world"
    try:
        status, headers, result = post_checksum(data)
        assert status == 200
        assert result == "3381945770", f"Expected checksum '3381945770', got '{result}'"
        assert headers.get_content_type() == "text/plain", "Checksum response is not plain text"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to the Nginx proxy or backend: {e}")

    payloads = [
        b"",
        os.urandom(1),
        os.urandom(37),
        os.urandom(4099),
        os.urandom(1024 * 1024),
    ]
    for payload in payloads:
        status, _, result = post_checksum(payload)
        expected = str(crc32c(payload))
        assert status == 200
        assert result == expected, \
            f"Wrong CRC32C for runtime-generated {len(payload)}-byte payload: expected {expected}, got {result}"


def test_nginx_method_not_allowed():
    """Test that Nginx rejects non-POST requests to /checksum."""
    req = urllib.request.Request(BASE_URL + "/checksum", method="GET")
    try:
        with urllib.request.urlopen(req) as response:
            pytest.fail(f"Expected HTTP 405 for GET request, but got {response.status}")
    except urllib.error.HTTPError as e:
        assert e.code == 405, f"Expected HTTP 405 Method Not Allowed, got {e.code}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx: {e}")


def test_nginx_body_size_limit():
    """Test that Nginx enforces the 5M client body size limit."""
    data = b"A" * (6 * 1024 * 1024)
    req = urllib.request.Request(BASE_URL + "/checksum", data=data, method="POST")
    try:
        with urllib.request.urlopen(req) as response:
            pytest.fail(f"Expected HTTP 413 Payload Too Large, but got {response.status}")
    except urllib.error.HTTPError as e:
        assert e.code == 413, f"Expected HTTP 413 Payload Too Large, got {e.code}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx: {e}")


def test_performance_metric():
    """Measure and validate every result for the 1MB benchmark payload."""
    payload = b"A" * 1024 * 1024
    expected = str(crc32c(payload))
    times = []

    try:
        status, _, result = post_checksum(payload)
        assert status == 200
        assert result == expected, f"Warm-up checksum was wrong: expected {expected}, got {result}"
    except Exception as e:
        pytest.fail(f"Warm-up request failed: {e}")

    for _ in range(50):
        start = time.time()
        try:
            status, _, result = post_checksum(payload)
            assert status == 200
            assert result == expected, f"Benchmark checksum was wrong: expected {expected}, got {result}"
        except Exception as e:
            pytest.fail(f"Benchmark request failed: {e}")
        times.append(time.time() - start)

    avg_latency_ms = (sum(times) / len(times)) * 1000
    threshold = 3.0
    assert avg_latency_ms <= threshold, (
        f"Performance metric failed: Average latency {avg_latency_ms:.2f} ms exceeds "
        f"the threshold of {threshold} ms. Ensure the C library is compiled with -O3 optimizations."
    )


def test_rate_limiting_is_enforced():
    """Send a burst well above the configured allowance and require Nginx rejections."""
    payload = os.urandom(64)

    def send_one(_):
        req = urllib.request.Request(BASE_URL + "/checksum", data=payload, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=10) as response:
                response.read()
                return response.status
        except urllib.error.HTTPError as e:
            e.read()
            return e.code
        except urllib.error.URLError:
            return None

    with concurrent.futures.ThreadPoolExecutor(max_workers=80) as pool:
        statuses = list(pool.map(send_one, range(400)))

    limited = sum(code in (429, 503) for code in statuses)
    successful = sum(code == 200 for code in statuses)
    assert successful > 0, f"No requests reached the service during rate-limit test: {statuses}"
    assert limited > 0, "Nginx did not reject any requests during a burst above 100 requests/second"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
