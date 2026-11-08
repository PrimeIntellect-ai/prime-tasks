#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import signal
import string
import subprocess
import time
import urllib.error
import urllib.request

import pytest
import redis

PROJECT = "/home/user/project"
BUILD = os.path.join(PROJECT, "build")
GATEWAY = os.path.join(BUILD, "gateway")
LIBRARY = os.path.join(BUILD, "libsanitiser.so")
PORTS = (6379, 5000, 8080)


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        if int(fields[1].rsplit(":", 1)[1], 16) == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def kill_services():
    pids = set()
    for port in PORTS:
        pids.update(listening_pids(port))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline:
        remaining = set()
        for port in PORTS:
            remaining.update(listening_pids(port))
        if not remaining:
            return
        time.sleep(0.1)
    for pid in remaining:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def wait_for_ports(timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if all(listening_pids(port) for port in PORTS):
            return
        time.sleep(0.1)
    missing = [str(port) for port in PORTS if not listening_pids(port)]
    pytest.fail("Services did not listen on ports: " + ", ".join(missing))


def run_checked(command, **kwargs):
    result = subprocess.run(command, text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(command)}\n"
        f"stdout:\n{getattr(result, 'stdout', '')}\n"
        f"stderr:\n{getattr(result, 'stderr', '')}"
    )
    return result


@pytest.fixture(scope="session", autouse=True)
def build_and_start_system():
    kill_services()
    try:
        os.makedirs(BUILD, exist_ok=True)
        for artifact in (LIBRARY, GATEWAY):
            try:
                os.remove(artifact)
            except FileNotFoundError:
                pass

        result = subprocess.run(
            ["make", "all"], cwd=PROJECT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
        )
        assert result.returncode == 0, (
            f"make all failed ({result.returncode})\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(LIBRARY), "make all did not create libsanitiser.so"
        assert os.path.isfile(GATEWAY), "make all did not create gateway"

        log_path = "/tmp/project-start.log"
        with open(log_path, "w") as log:
            try:
                result = subprocess.run(
                    ["bash", os.path.join(PROJECT, "start.sh")],
                    cwd=PROJECT, stdout=log, stderr=subprocess.STDOUT, timeout=30
                )
            except subprocess.TimeoutExpired:
                pytest.fail("start.sh did not finish after starting its background services")
        if result.returncode != 0:
            with open(log_path, errors="replace") as log:
                pytest.fail(f"start.sh failed ({result.returncode}):\n{log.read()}")

        wait_for_ports()
        yield
    finally:
        kill_services()


def test_build_artifacts_exist():
    assert os.path.isfile("/home/user/project/Makefile"), "Makefile is missing"
    assert os.path.isfile("/home/user/project/start.sh"), "start.sh is missing"
    assert os.path.isfile("/home/user/project/build/libsanitiser.so"), "libsanitiser.so was not built"
    assert os.path.isfile("/home/user/project/build/gateway"), "Go gateway executable was not built"
    assert os.path.isfile("/home/user/project/src/sanitiser.cpp"), "sanitiser.cpp is missing"
    assert os.path.isfile("/home/user/project/src/sanitiser.h"), "sanitiser.h is missing"


def test_artifacts_are_real_and_dynamically_linked():
    assert open(LIBRARY, "rb").read(4) == b"\x7fELF", "libsanitiser.so is not an ELF library"
    assert open(GATEWAY, "rb").read(4) == b"\x7fELF", "gateway is not an ELF executable"
    assert os.access(GATEWAY, os.X_OK), "gateway is not executable"

    lib_header = run_checked(["readelf", "-h", LIBRARY], capture_output=True).stdout
    assert "DYN (Shared object file)" in lib_header, "libsanitiser.so is not a shared object"

    symbols = run_checked(["nm", "-D", "--defined-only", LIBRARY], capture_output=True).stdout
    assert any(line.split()[-1] == "is_safe_payload" for line in symbols.splitlines() if line.split()), \
        "libsanitiser.so does not export is_safe_payload"

    dynamic = run_checked(["readelf", "-d", GATEWAY], capture_output=True).stdout
    assert "libsanitiser.so" in dynamic, "gateway has no dynamic dependency on libsanitiser.so"

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = BUILD + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    linked = run_checked(["ldd", GATEWAY], capture_output=True, env=env).stdout
    matching = [line for line in linked.splitlines() if "libsanitiser.so" in line]
    assert matching and "not found" not in matching[0], "gateway cannot resolve libsanitiser.so"
    assert os.path.realpath(LIBRARY) in matching[0], "gateway resolves a different sanitiser library"


def test_started_expected_services():
    gateway_pids = listening_pids(8080)
    assert gateway_pids, "nothing is listening on gateway port 8080"
    matching_gateway = False
    for pid in gateway_pids:
        try:
            matching_gateway |= os.path.samefile(f"/proc/{pid}/exe", GATEWAY)
        except (FileNotFoundError, OSError):
            pass
    assert matching_gateway, "port 8080 is not served by the freshly built gateway executable"

    backend_pids = listening_pids(5000)
    assert backend_pids, "nothing is listening on backend port 5000"
    expected_backend = os.path.join(PROJECT, "backend", "app.py")
    matching_backend = False
    for pid in backend_pids:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            cwd = os.readlink(f"/proc/{pid}/cwd")
            for arg in args[1:]:
                if arg.endswith(".py"):
                    candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
                    if os.path.exists(candidate) and os.path.samefile(candidate, expected_backend):
                        matching_backend = True
        except (FileNotFoundError, OSError):
            pass
    assert matching_backend, "port 5000 is not served by the provided backend/app.py"

    redis_pids = listening_pids(6379)
    assert redis_pids, "nothing is listening on Redis port 6379"
    assert any("redis-server" in os.path.basename(os.readlink(f"/proc/{pid}/exe"))
               for pid in redis_pids if os.path.exists(f"/proc/{pid}/exe")), \
        "port 6379 is not served by redis-server"


def test_sanitiser_library_on_derived_inputs():
    library = ctypes.CDLL(LIBRARY)
    classify = library.is_safe_payload
    classify.argtypes = [ctypes.c_char_p]
    classify.restype = ctypes.c_bool

    forbidden = b"|;&$><`"
    safe_alphabet = (string.ascii_letters + string.digits + " _-+=:,.!?/()[]{}'\\\"\\\n\\t").encode()
    rng = secrets.SystemRandom()

    samples = [b""]
    for _ in range(100):
        samples.append(bytes(rng.choice(safe_alphabet) for _ in range(rng.randrange(0, 100))))
    for marker in forbidden:
        for _ in range(20):
            prefix = bytes(rng.choice(safe_alphabet) for _ in range(rng.randrange(0, 50)))
            suffix = bytes(rng.choice(safe_alphabet) for _ in range(rng.randrange(0, 50)))
            samples.append(prefix + bytes([marker]) + suffix)

    rng.shuffle(samples)
    for payload in samples:
        expected = not any(marker in payload for marker in forbidden)
        assert bool(classify(payload)) == expected, f"wrong classification for {payload!r}"


def request_status(url, payload):
    req = urllib.request.Request(url, data=payload, method="POST", headers={"Content-Type": "text/plain"})
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


def test_backend_and_randomized_end_to_end_behavior():
    cache = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=3)
    assert cache.ping(), "Redis did not answer PING"

    direct_payload = ("backend-check-" + secrets.token_hex(12)).encode()
    assert request_status("http://127.0.0.1:5000/api", direct_payload) == 200
    assert cache.get("latest_payload") == direct_payload, "backend did not write its payload to Redis"

    rng = secrets.SystemRandom()
    safe_alphabet = (string.ascii_letters + string.digits + " _-+=:,.!?/()[]{}'\\\"").encode()
    forbidden = b"|;&$><`"
    gateway_url = "http://127.0.0.1:8080/process"

    clean_payloads = []
    for _ in range(35):
        clean_payloads.append(bytes(rng.choice(safe_alphabet) for _ in range(rng.randrange(1, 90))))

    evil_payloads = []
    for marker in forbidden:
        for _ in range(10):
            prefix = bytes(rng.choice(safe_alphabet) for _ in range(rng.randrange(0, 40)))
            suffix = bytes(rng.choice(safe_alphabet) for _ in range(rng.randrange(0, 40)))
            evil_payloads.append(prefix + bytes([marker]) + suffix)

    for payload in clean_payloads:
        assert request_status(gateway_url, payload) == 200, f"gateway rejected clean payload {payload!r}"
        assert cache.get("latest_payload") == payload, "accepted payload was not forwarded through the backend to Redis"

    for payload in evil_payloads:
        sentinel = ("sentinel-" + secrets.token_hex(10)).encode()
        cache.set("latest_payload", sentinel)
        assert request_status(gateway_url, payload) == 403, f"gateway accepted unsafe payload {payload!r}"
        time.sleep(0.05)
        assert cache.get("latest_payload") == sentinel, "unsafe payload reached the backend/Redis"


def test_adversarial_corpus():
    clean_dir = "/home/user/corpora/clean/"
    evil_dir = "/home/user/corpora/evil/"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) > 0, "No clean corpus files found"
    assert len(evil_files) > 0, "No evil corpus files found"

    url = "http://127.0.0.1:8080/process"

    failed_clean = []
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        with open(filepath, "rb") as f:
            data = f.read()

        req = urllib.request.Request(url, data=data, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status != 200:
                    failed_clean.append(filename)
        except urllib.error.HTTPError:
            failed_clean.append(filename)
        except Exception as e:
            failed_clean.append(f"{filename} (connection error: {e})")

    failed_evil = []
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        with open(filepath, "rb") as f:
            data = f.read()

        req = urllib.request.Request(url, data=data, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status != 403:
                    failed_evil.append(filename)
        except urllib.error.HTTPError as e:
            if e.code != 403:
                failed_evil.append(filename)
        except Exception as e:
            failed_evil.append(f"{filename} (connection error: {e})")

    error_messages = []
    if failed_evil:
        error_messages.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")
    if failed_clean:
        error_messages.append(f"{len(failed_clean)} of {len(clean_files)} clean modified or rejected: {', '.join(failed_clean)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
