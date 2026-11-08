#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import shutil
import socket
import stat
import string
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

WORKSPACE = "/home/user/workspace"
BUILD = os.path.join(WORKSPACE, "build")
ORACLE = "/home/user/oracle_hash"
CLI = os.path.join(BUILD, "compute_hash")
LIB = os.path.join(BUILD, "libmathops.so")
APP = os.path.join(WORKSPACE, "api", "app.py")
URL = "http://127.0.0.1:5000/hash"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kwargs)


def expected_hash(data):
    p = run([ORACLE, data])
    return int(p.stdout.strip())


def stop_flask():
    subprocess.run(
        ["pkill", "-f", "python3 .*api/app.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    time.sleep(0.5)


def start_flask():
    stop_flask()
    log = open("/tmp/verifier-flask.log", "ab", buffering=0)
    proc = subprocess.Popen(
        ["python3", APP], cwd=WORKSPACE, stdout=log, stderr=log,
        start_new_session=True,
    )
    deadline = time.time() + 10
    while time.time() < deadline:
        if proc.poll() is not None:
            log.close()
            raise AssertionError("Flask application exited during startup")
        try:
            with socket.create_connection(("127.0.0.1", 5000), timeout=0.25):
                return proc, log
        except OSError:
            time.sleep(0.1)
    proc.terminate()
    log.close()
    raise AssertionError("Flask application did not listen on 127.0.0.1:5000")


def stop_started_flask(proc, log):
    try:
        proc.terminate()
        proc.wait(timeout=3)
    except Exception:
        proc.kill()
        proc.wait(timeout=3)
    finally:
        log.close()


def post_hash(value):
    body = urllib.parse.urlencode({"data": value}).encode("utf-8")
    req = urllib.request.Request(URL, data=body)
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.status == 200
        return json.loads(response.read().decode("utf-8"))


def ensure_redis():
    ping = subprocess.run(["redis-cli", "-p", "6379", "ping"], capture_output=True, text=True)
    if ping.returncode != 0 or ping.stdout.strip() != "PONG":
        run(["redis-server", "--port", "6379", "--daemonize", "yes"])
        deadline = time.time() + 5
        while time.time() < deadline:
            ping = subprocess.run(["redis-cli", "-p", "6379", "ping"], capture_output=True, text=True)
            if ping.returncode == 0 and ping.stdout.strip() == "PONG":
                break
            time.sleep(0.1)
        else:
            raise AssertionError("Redis is not available on port 6379")


def test_01_clean_cmake_build_and_artifacts():
    assert os.path.isfile(ORACLE), f"Oracle binary not found at {ORACLE}"

    shutil.rmtree(BUILD, ignore_errors=True)
    os.makedirs(BUILD)
    run(["cmake", ".."], cwd=BUILD)
    run(["make", "-j2"], cwd=BUILD)

    for path in (CLI, LIB):
        info = os.lstat(path)
        assert stat.S_ISREG(info.st_mode), f"{path} must be a regular build artifact"
        assert os.path.getsize(path) > 0, f"{path} is empty"
    assert os.access(CLI, os.X_OK), f"Agent binary at {CLI} is not executable"
    assert open(CLI, "rb").read(4) == b"\x7fELF", "compute_hash is not an ELF executable"
    assert open(LIB, "rb").read(4) == b"\x7fELF", "libmathops.so is not an ELF shared library"
    assert open(CLI, "rb").read() != open(ORACLE, "rb").read(), "compute_hash is a copy of the oracle"

    dynamic = run(["readelf", "-d", CLI]).stdout
    assert "libmathops.so" in dynamic, "compute_hash is not dynamically linked to libmathops.so"
    symbols = run(["nm", "-D", CLI]).stdout
    assert any(" U compute_hash" in line for line in symbols.splitlines()), \
        "compute_hash executable does not call the shared-library compute_hash symbol"
    exported = run(["nm", "-D", LIB]).stdout
    assert any(" T compute_hash" in line or " W compute_hash" in line for line in exported.splitlines()), \
        "libmathops.so does not export compute_hash"

    interposer_c = "/tmp/hash_interposer.c"
    interposer_so = "/tmp/hash_interposer.so"
    with open(interposer_c, "w") as f:
        f.write('#include <stdint.h>\n#include <stddef.h>\nuint32_t compute_hash(const char *p, size_t n) {(void)p; (void)n; return 324508639U;}\n')
    run(["gcc", "-shared", "-fPIC", interposer_c, "-o", interposer_so])
    env = os.environ.copy()
    env["LD_PRELOAD"] = interposer_so
    probe = run([CLI, "must-use-the-shared-library"], env=env)
    assert probe.stdout.strip() == "324508639", \
        "compute_hash CLI did not use the linked shared-library function result"


def test_02_fuzz_equivalence():
    assert os.path.isfile(ORACLE), f"Oracle binary not found at {ORACLE}"
    assert os.path.isfile(CLI), f"Agent binary not found at {CLI}"
    assert os.access(CLI, os.X_OK), f"Agent binary at {CLI} is not executable"

    random.seed(42)
    alphanumeric = string.ascii_letters + string.digits
    for _ in range(1000):
        length = random.randint(1, 1024)
        test_input = ''.join(random.choices(alphanumeric, k=length))
        oracle_proc = subprocess.run([ORACLE, test_input], capture_output=True, text=True, check=False)
        agent_proc = subprocess.run([CLI, test_input], capture_output=True, text=True, check=False)
        assert oracle_proc.returncode == 0, f"Oracle failed on input: {test_input}"
        assert agent_proc.returncode == 0, f"Agent failed on input: {test_input}"
        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()
        assert oracle_out == agent_out, (
            f"Mismatch on input '{test_input}'. Oracle output: '{oracle_out}', "
            f"Agent output: '{agent_out}'"
        )


def test_03_shared_library_directly():
    lib = ctypes.CDLL(LIB)
    fn = lib.compute_hash
    fn.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
    fn.restype = ctypes.c_uint32
    random.seed(8192)
    alphabet = string.ascii_letters + string.digits
    for _ in range(100):
        value = ''.join(random.choices(alphabet, k=random.randint(1, 300)))
        raw = value.encode("utf-8")
        assert fn(raw, len(raw)) == expected_hash(value)


def test_04_api_uses_ctypes_library_with_correct_signature():
    ensure_redis()
    stop_flask()
    run(["redis-cli", "-p", "6379", "FLUSHALL"])

    real_lib = LIB + ".verifier-real"
    marker = "/tmp/ffi-marker"
    stub_c = "/tmp/ffi_stub.c"
    if os.path.exists(marker):
        os.unlink(marker)
    os.rename(LIB, real_lib)
    try:
        with open(stub_c, "w") as f:
            f.write(r'''#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
uint32_t compute_hash(const char *data, size_t len) {
    FILE *fp = fopen("/tmp/ffi-marker", "wb");
    if (fp) { fprintf(fp, "%zu\n", len); fwrite(data, 1, len, fp); fclose(fp); }
    return 4000000001U;
}
''')
        run(["gcc", "-shared", "-fPIC", stub_c, "-o", LIB])
        proc, log = start_flask()
        try:
            value = "CtypesProbe_7Kq9"
            response = post_hash(value)
            assert response.get("hash") == 4000000001, \
                "API did not return the uint32 result from libmathops.so"
            assert response.get("cached") is False, "First uncached API request must report cached=false"
            assert os.path.isfile(marker), "libmathops compute_hash was not called by the API"
            with open(marker, "rb") as f:
                marker_data = f.read()
            assert marker_data == (str(len(value.encode())).encode() + b"\n" + value.encode()), \
                "API passed incorrect data or length through ctypes"
        finally:
            stop_started_flask(proc, log)
    finally:
        if os.path.exists(LIB):
            os.unlink(LIB)
        os.rename(real_lib, LIB)


def test_05_api_integration_and_real_redis_caching():
    ensure_redis()
    run(["redis-cli", "-p", "6379", "FLUSHALL"])
    proc, log = start_flask()
    try:
        random.seed(1337)
        alphanumeric = string.ascii_letters + string.digits
        test_input = ''.join(random.choices(alphanumeric, k=50))
        expected = expected_hash(test_input)

        res1 = post_hash(test_input)
        assert 'hash' in res1, "API response missing 'hash' key"
        assert res1['hash'] == expected, f"API returned wrong hash. Expected {expected}, got {res1['hash']}"
        assert res1.get('cached') is False, "First request after Redis flush must not be cached"

        stored = run(["redis-cli", "-p", "6379", "--raw", "GET", test_input]).stdout.strip()
        assert stored == str(expected), "API did not store the computed hash in local Redis"

        res2 = post_hash(test_input)
        assert res2.get('cached') is True, "Second API request did not return 'cached': true"
        assert res2['hash'] == expected, f"API returned wrong hash on cached request. Expected {expected}, got {res2['hash']}"

        alternate = (expected + 1) & 0xffffffff
        run(["redis-cli", "-p", "6379", "SET", test_input, str(alternate)])
        res3 = post_hash(test_input)
        assert res3.get('cached') is True, "API did not identify a Redis cache hit"
        assert res3.get('hash') == alternate, "API did not read the cached value from Redis"
    finally:
        stop_started_flask(proc, log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
