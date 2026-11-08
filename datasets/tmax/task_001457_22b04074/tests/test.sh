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
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import subprocess
import time

import pytest
import requests


def wait_for_service(url, timeout=5):
    """Wait for the service to become available."""
    start = time.time()
    while time.time() - start < timeout:
        try:
            r = requests.get(url, timeout=1)
            if r.status_code == 200:
                return True
        except requests.exceptions.RequestException:
            pass
        time.sleep(0.5)
    return False


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def process_exe(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return ""


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def expected_embedding(entity_id):
    raw = [float(entity_id + i) for i in range(3)]
    norm = math.sqrt(sum(x * x for x in raw))
    return [x / norm for x in raw]


def assert_response(response, entity_id):
    assert response.status_code == 200, f"Expected HTTP 200 for id {entity_id}, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert set(data.keys()) == {"id", "embedding"}, "HTTP JSON response format was altered"
    assert type(data["id"]) is int, "'id' must be a JSON integer"
    assert data["id"] == entity_id, f"Returned id {data['id']} does not match requested id {entity_id}"

    embedding = data["embedding"]
    assert isinstance(embedding, list), "'embedding' should be a list"
    assert len(embedding) == 3, f"Expected an embedding of length 3, got {len(embedding)}"
    assert all(type(x) is float for x in embedding), "Embedding entries must be JSON floating-point values"

    expected = expected_embedding(entity_id)
    for index, (actual, wanted) in enumerate(zip(embedding, expected)):
        assert math.isclose(actual, wanted, rel_tol=3e-6, abs_tol=3e-6), (
            f"Embedding value {index} for id {entity_id} is {actual}, expected {wanted}"
        )

    sq_sum = sum(x * x for x in embedding)
    norm = math.sqrt(sq_sum)
    assert math.isclose(norm, 1.0, rel_tol=1e-3, abs_tol=1e-3), (
        f"L2 norm of embedding for id {entity_id} is {norm}, expected ~1.0"
    )
    assert any(x != 0.0 for x in embedding), "Embedding values are all zero, precision bug not fixed"
    assert any(not float(x).is_integer() for x in embedding), (
        "Embedding values appear to be truncated to integers, precision bug not fixed"
    )
    return data


def test_required_artifacts_and_running_processes():
    assert os.path.isfile("/app/server.c"), "/app/server.c is missing"
    assert os.path.isfile("/app/server"), "Compiled /app/server is missing"
    assert os.access("/app/server", os.X_OK), "/app/server is not executable"
    with open("/app/server", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/app/server is not a compiled ELF executable"
    assert os.path.isfile("/app/nginx.conf"), "/app/nginx.conf is missing"

    backend_pids = listening_pids(9000)
    assert backend_pids, "No process is listening on backend port 9000"
    assert any(process_exe(pid) == "/app/server" for pid in backend_pids), (
        "Port 9000 is not being served by the compiled /app/server binary"
    )

    gateway_pids = listening_pids(8080)
    assert gateway_pids, "No process is listening on gateway port 8080"
    assert any(os.path.basename(process_exe(pid)) == "nginx" for pid in gateway_pids), (
        "Port 8080 is not being served by Nginx"
    )

    nginx_pids = [int(p) for p in os.listdir("/proc") if p.isdigit() and os.path.basename(process_exe(int(p))) == "nginx"]
    assert any("/app/nginx.conf" in process_cmdline(pid) for pid in nginx_pids), (
        "Running Nginx was not started using /app/nginx.conf"
    )


def test_nginx_configuration_really_proxies_to_backend():
    result = subprocess.run(
        ["nginx", "-T", "-c", "/app/nginx.conf"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=5,
    )
    assert result.returncode == 0, f"/app/nginx.conf is invalid:\n{result.stdout}"
    normalized = re.sub(r"\s+", " ", result.stdout)
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:9000\s*;", normalized), (
        "/app/nginx.conf does not proxy requests to http://127.0.0.1:9000"
    )


def test_source_normalization_function():
    harness = r'''\
#define main embedded_server_main
#include "/app/server.c"
#undef main
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    if (argc != 4) return 2;
    float v[3] = {(float)atof(argv[1]), (float)atof(argv[2]), (float)atof(argv[3])};
    normalize_embedding(v, 3);
    printf("%.9g %.9g %.9g\n", v[0], v[1], v[2]);
    return 0;
}
'''
    with open("/tmp/normalize_harness.c", "w") as f:
        f.write(harness)
    build = subprocess.run(
        ["gcc", "/tmp/normalize_harness.c", "-lm", "-o", "/tmp/normalize_harness"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
    )
    assert build.returncode == 0, f"/app/server.c does not compile correctly:\n{build.stdout}"

    values = [float(random.SystemRandom().randint(3, 5000) + i) for i in range(3)]
    run = subprocess.run(
        ["/tmp/normalize_harness", *(str(x) for x in values)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=5,
    )
    assert run.returncode == 0, f"normalize_embedding harness failed: {run.stdout}"
    try:
        actual = [float(x) for x in run.stdout.split()]
    except ValueError:
        pytest.fail(f"normalize_embedding produced invalid output: {run.stdout}")
    assert len(actual) == 3
    norm = math.sqrt(sum(x * x for x in values))
    expected = [x / norm for x in values]
    for got, wanted in zip(actual, expected):
        assert math.isclose(got, wanted, rel_tol=3e-6, abs_tol=3e-6), (
            f"normalize_embedding in /app/server.c returned {actual}, expected {expected}"
        )


def test_nginx_proxy_and_backend_response():
    url = "http://127.0.0.1:8080/embed?id=1"
    wait_for_service(url)
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx on port 8080: {e}")
    assert_response(response, 1)
    assert "nginx" in response.headers.get("Server", "").lower(), "Gateway response was not emitted by Nginx"


def test_multiple_ids():
    for test_id in [5, 10, 42]:
        try:
            response = requests.get(f"http://127.0.0.1:8080/embed?id={test_id}", timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to Nginx for id {test_id}: {e}")
        assert_response(response, test_id)


def test_derived_unpredictable_requests_through_proxy_and_backend():
    ids = random.SystemRandom().sample(range(50, 10000), 6)
    returned = []
    for entity_id in ids:
        try:
            direct = requests.get(f"http://127.0.0.1:9000/embed?id={entity_id}", timeout=2)
            proxied = requests.get(f"http://127.0.0.1:8080/embed?id={entity_id}", timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Request for derived id {entity_id} failed: {e}")
        direct_data = assert_response(direct, entity_id)
        proxied_data = assert_response(proxied, entity_id)
        assert proxied_data == direct_data, "Nginx response differs from the C backend response"
        returned.append(tuple(proxied_data["embedding"]))
    assert len(set(returned)) == len(ids), "Different entity IDs returned a constant embedding"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
