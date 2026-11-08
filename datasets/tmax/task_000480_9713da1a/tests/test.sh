#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import random
import shutil
import subprocess
import time
import urllib.request
import pytest

APP_DIR = "/home/user/app"
LIB_PATH = "/home/user/app/c_src/libpoly.so"
REFERENCE_PATH = "/home/user/app/reference.py"


def expected_output(n, m):
    values = [math.sin(i) * 100.0 for i in range(n)]
    values += [math.cos(j) * 100.0 for j in range(m)]
    return sorted(values)[-10:]


def fetch(n, m, timeout=5):
    url = f"http://localhost:8080/api/merge?n={n}&m={m}"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        assert response.status == 200, f"HTTP status was {response.status} for {url}"
        return response.read().decode("utf-8").strip()


def redis_cli(*args):
    return subprocess.check_output(["redis-cli", *map(str, args)]).decode("utf-8").strip()


def stop_gunicorn():
    subprocess.run(["pkill", "-TERM", "-f", "gunicorn.*api:app"], check=False)
    time.sleep(1)
    subprocess.run(["pkill", "-KILL", "-f", "gunicorn.*api:app"], check=False)
    time.sleep(0.5)


def start_gunicorn():
    subprocess.check_call(
        ["gunicorn", "-w", "2", "-b", "127.0.0.1:5000", "api:app", "--daemon"],
        cwd=APP_DIR,
    )


def wait_for_api(n=10, m=10):
    last_error = None
    for _ in range(40):
        try:
            fetch(n, m, timeout=1)
            return
        except Exception as exc:
            last_error = exc
            time.sleep(0.25)
    raise AssertionError(f"API did not become ready: {last_error}")


def test_services_running():
    try:
        output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
        assert "redis-server" in output, "Redis server is not running."
        assert "nginx" in output, "Nginx is not running."
        assert "gunicorn" in output, "Gunicorn is not running."
    except Exception as e:
        pytest.fail(f"Failed to check running services: {e}")


def test_libpoly_compiled():
    assert os.path.exists(LIB_PATH), f"{LIB_PATH} does not exist. Did you run make?"
    output = subprocess.check_output(["file", LIB_PATH]).decode("utf-8")
    assert "shared object" in output, f"{LIB_PATH} is not compiled as a shared object (-shared)."


def test_libpoly_exports_and_computes():
    lib = ctypes.CDLL(LIB_PATH)
    assert hasattr(lib, "compute_and_merge"), "libpoly.so does not export compute_and_merge"
    fn = lib.compute_and_merge
    fn.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.c_double)]
    fn.restype = None

    random.seed(9173)
    cases = [(10, 10), (1000, 1000)]
    cases += [(random.randint(10, 1000), random.randint(10, 1000)) for _ in range(30)]
    for n, m in cases:
        output = (ctypes.c_double * 10)()
        fn(n, m, output)
        assert list(output) == expected_output(n, m), (
            f"compute_and_merge returned incorrect doubles for n={n}, m={m}"
        )


def test_fuzz_equivalence():
    random.seed(42)
    for _ in range(100):
        n = random.randint(10, 1000)
        m = random.randint(10, 1000)
        derived_output = json.dumps(expected_output(n, m), separators=(",", ":"))

        try:
            oracle_output = subprocess.check_output(
                [REFERENCE_PATH, str(n), str(m)]
            ).decode("utf-8").strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed for N={n}, M={m}: {e}")

        assert oracle_output == derived_output, (
            f"The on-image reference was modified or disagrees with the derived result for N={n}, M={m}."
        )

        try:
            agent_output = fetch(n, m)
        except Exception as e:
            pytest.fail(f"Agent HTTP request failed for N={n}, M={m}: {e}")

        assert agent_output == oracle_output, (
            f"Mismatch for N={n}, M={m}.\n"
            f"Oracle: {oracle_output}\n"
            f"Agent:  {agent_output}"
        )


def test_redis_caching():
    n, m = 999, 998
    key = f"poly_merge:{n}:{m}"
    redis_cli("del", key)

    try:
        first_response = fetch(n, m)
    except Exception as e:
        pytest.fail(f"Agent HTTP request failed for cache test: {e}")

    try:
        redis_output = redis_cli("get", key)
        assert redis_output != "", "Redis cache is empty for the requested key."
        assert redis_output != "(nil)", f"Redis cache returned (nil) for key {key}."
        cached_data = json.loads(redis_output)
        assert isinstance(cached_data, list), "Cached data is not a JSON list."
        assert redis_output == first_response, "Redis did not store the exact JSON response string."

        ttl = int(redis_cli("ttl", key))
        assert 1 <= ttl <= 60, f"Cache key has incorrect TTL {ttl}; expected an expiration of 60 seconds."

        sentinel = "[12345.25,-7.5,88.125]"
        subprocess.check_call(["redis-cli", "set", key, sentinel, "EX", "60"], stdout=subprocess.DEVNULL)
        second_response = fetch(n, m)
        assert second_response == sentinel, (
            "A pre-populated Redis value was not returned; cache hits are not being served from Redis."
        )
    except Exception as e:
        pytest.fail(f"Redis cache check failed: {e}")


def test_api_result_is_produced_by_ctypes_library(tmp_path):
    probe_c = tmp_path / "probe.c"
    probe_so = tmp_path / "libpoly_probe.so"
    backup = tmp_path / "libpoly_original.so"
    probe_c.write_text(
        "void compute_and_merge(int n, int m, double *out) {\n"
        "  for (int i = 0; i < 10; ++i)\n"
        "    out[i] = 1000000.0 + (double)n * 1000.0 + (double)m + (double)i / 16.0;\n"
        "}\n"
    )
    subprocess.check_call(["gcc", "-shared", "-fPIC", "-o", str(probe_so), str(probe_c)])
    shutil.copy2(LIB_PATH, backup)

    n, m = 731, 643
    key = f"poly_merge:{n}:{m}"
    expected = [1000000.0 + n * 1000.0 + m + i / 16.0 for i in range(10)]

    stop_gunicorn()
    try:
        os.replace(probe_so, LIB_PATH)
        redis_cli("del", key)
        start_gunicorn()
        wait_for_api(n, m)
        actual_text = fetch(n, m)
        actual = json.loads(actual_text)
        assert actual == expected, (
            "Replacing compute_and_merge changed no API result; the API is not using the required "
            "ctypes call to /home/user/app/c_src/libpoly.so."
        )
    finally:
        stop_gunicorn()
        if backup.exists():
            os.replace(backup, LIB_PATH)
        redis_cli("del", key)
        start_gunicorn()
        wait_for_api()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
