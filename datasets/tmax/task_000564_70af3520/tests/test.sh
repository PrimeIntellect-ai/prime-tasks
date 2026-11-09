#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import re
import secrets
import socket
import stat
import subprocess
import time
import urllib.error
import urllib.request

import pytest

PROJECT = "/home/user/project"
LIB = PROJECT + "/libfilter.so"
SERVICE = PROJECT + "/service/target/release/math_service"
URL = "http://127.0.0.1:8080/eval"
DIRECT_URL = "http://127.0.0.1:3000/eval"


def make_valid_cases():
    rng = random.SystemRandom()

    def number():
        return "".join(rng.choice("0123456789") for _ in range(rng.randint(1, 4)))

    def expression(depth=0):
        parts = []
        count = rng.randint(1, 3)
        for i in range(count):
            if depth < 4 and rng.random() < 0.35:
                value = "(" + expression(depth + 1) + ")"
            else:
                value = number()
            parts.append((" " * rng.randint(0, 2)) + value + (" " * rng.randint(0, 2)))
            if i + 1 < count:
                parts.append(rng.choice(["+", "-", "*", "/"]))
        return "".join(parts)

    cases = set()
    while len(cases) < 70:
        value = expression()
        if 0 < len(value) <= 50:
            cases.add(value)
    for _ in range(8):
        cases.add("(" * 5 + number() + ")" * 5)
    return list(cases)


def make_invalid_cases(valid_cases):
    rng = random.SystemRandom()
    forbidden = list("abcXYZ_;|&$%![]{}\\'\"\t\n")
    cases = set()
    for value in rng.sample(valid_cases, min(45, len(valid_cases))):
        pos = rng.randrange(len(value) + 1)
        cases.add(value[:pos] + rng.choice(forbidden) + value[pos:])
    for _ in range(12):
        cases.add("".join(rng.choice("0123456789") for _ in range(rng.randint(51, 75))))
        inner = str(rng.randint(0, 999999))
        cases.add("(" * 6 + inner + ")" * 6)
        cases.add("(" * rng.randint(1, 5) + inner + ")" * rng.randint(0, 4))
        cases.add(inner + ")")
    return list(cases)


VALID_CASES = make_valid_cases()
INVALID_CASES = make_invalid_cases(VALID_CASES)


def wait_for_port(port, process=None, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process is not None and process.poll() is not None:
            pytest.fail(f"process exited before opening port {port} (status {process.returncode})")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"port {port} did not become available")


@pytest.fixture(scope="session", autouse=True)
def build_and_start_submission():
    subprocess.run(["pkill", "-x", "math_service"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.2)

    for path in (LIB, SERVICE):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(["make", "-C", PROJECT], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=240)
    assert result.returncode == 0, "Makefile build failed:\n" + result.stdout

    assert os.path.isfile(LIB), "Makefile did not build libfilter.so"
    assert os.path.isfile(SERVICE), "Makefile did not build math_service"
    assert os.access(SERVICE, os.X_OK), "math_service is not executable"
    with open(SERVICE, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "math_service is not an ELF executable"

    dynamic = subprocess.run(["readelf", "-d", SERVICE], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert dynamic.returncode == 0, "readelf could not inspect math_service"
    assert "libfilter.so" in dynamic.stdout, "math_service is not dynamically linked to libfilter.so"

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = PROJECT + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    backend_log = open("/tmp/math_service.verifier.log", "wb")
    backend = subprocess.Popen([SERVICE], cwd=PROJECT + "/service", env=env,
                               stdout=backend_log, stderr=subprocess.STDOUT)
    wait_for_port(3000, backend)
    assert os.path.realpath(f"/proc/{backend.pid}/exe") == os.path.realpath(SERVICE), \
        "the built math_service process is not the process started for the backend"

    nginx_test = subprocess.run(["nginx", "-t"], text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT)
    assert nginx_test.returncode == 0, "nginx configuration is invalid:\n" + nginx_test.stdout
    if subprocess.run(["pgrep", "-x", "nginx"], stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL).returncode == 0:
        reload_result = subprocess.run(["nginx", "-s", "reload"], text=True,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert reload_result.returncode == 0, "could not reload nginx:\n" + reload_result.stdout
    else:
        start_result = subprocess.run(["nginx"], text=True, stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT)
        assert start_result.returncode == 0, "could not start nginx:\n" + start_result.stdout
    wait_for_port(8080)

    yield
    backend_log.close()


def load_filter():
    try:
        lib = ctypes.CDLL(LIB)
    except Exception as exc:
        pytest.fail(f"Failed to load {LIB}: {exc}")
    assert hasattr(lib, "validate_math"), "validate_math function not found in libfilter.so"
    lib.validate_math.argtypes = [ctypes.c_char_p]
    lib.validate_math.restype = ctypes.c_int
    return lib


def post(url, content, timeout=3):
    request = urllib.request.Request(url, data=content, method="POST")
    return urllib.request.urlopen(request, timeout=timeout)


def test_makefile_exists():
    assert os.path.exists("/home/user/project/Makefile"), "Makefile is missing"


def test_libfilter_so_exists():
    assert os.path.exists(LIB), "libfilter.so is missing. Did the Makefile build it?"


def test_rust_service_exists():
    assert os.path.exists(SERVICE), "math_service executable is missing"


def test_nginx_config():
    config = "/etc/nginx/sites-enabled/math_proxy"
    assert os.path.exists(config), "Nginx config /etc/nginx/sites-enabled/math_proxy is missing"
    with open(config, "r", errors="replace") as handle:
        text = handle.read()
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:3000\s*;", text), \
        "math_proxy does not proxy to 127.0.0.1:3000"
    dump = subprocess.run(["nginx", "-T"], text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT)
    assert dump.returncode == 0
    assert "configuration file /etc/nginx/sites-enabled/math_proxy" in dump.stdout, \
        "math_proxy is not loaded by nginx"


def test_nginx_owns_listening_port_8080():
    listen_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table) as handle:
            next(handle)
            for line in handle:
                fields = line.split()
                if fields[3] == "0A" and int(fields[1].rsplit(":", 1)[1], 16) == 8080:
                    listen_inodes.add(fields[9])
    assert listen_inodes, "nothing is listening on TCP port 8080"

    nginx_owns_socket = False
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/comm") as handle:
                if handle.read().strip() != "nginx":
                    continue
            for fd in os.listdir(f"/proc/{pid}/fd"):
                try:
                    target = os.readlink(f"/proc/{pid}/fd/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in listen_inodes:
                    nginx_owns_socket = True
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if nginx_owns_socket:
            break
    assert nginx_owns_socket, "port 8080 is not being served by an nginx process"


def test_ctypes_validate_math():
    lib = load_filter()
    clean_dir = "/home/user/corpora/clean"
    evil_dir = "/home/user/corpora/evil"

    clean_failed = []
    for name in os.listdir(clean_dir):
        with open(os.path.join(clean_dir, name), "rb") as file:
            if lib.validate_math(file.read().strip()) != 1:
                clean_failed.append(name)

    evil_failed = []
    for name in os.listdir(evil_dir):
        with open(os.path.join(evil_dir, name), "rb") as file:
            if lib.validate_math(file.read().strip()) != 0:
                evil_failed.append(name)

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} evil bypassed: {', '.join(evil_failed)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_ctypes_randomized_validator_cases():
    lib = load_filter()
    rejected = [value for value in VALID_CASES if lib.validate_math(value.encode()) != 1]
    accepted = [value for value in INVALID_CASES if lib.validate_math(value.encode()) != 0]
    assert not rejected, f"validate_math rejected generated valid expression: {rejected[0]!r}"
    assert not accepted, f"validate_math accepted generated invalid expression: {accepted[0]!r}"


def test_web_endpoint():
    clean_dir = "/home/user/corpora/clean"
    evil_dir = "/home/user/corpora/evil"

    clean_failed = []
    for name in os.listdir(clean_dir):
        with open(os.path.join(clean_dir, name), "rb") as file:
            content = file.read().strip()
        try:
            with post(URL, content) as response:
                if response.status != 200 or response.read().strip() != b"42":
                    clean_failed.append(name)
        except Exception:
            clean_failed.append(name)

    evil_failed = []
    for name in os.listdir(evil_dir):
        with open(os.path.join(evil_dir, name), "rb") as file:
            content = file.read().strip()
        try:
            with post(URL, content) as response:
                if response.status == 200:
                    evil_failed.append(name)
        except urllib.error.HTTPError as exc:
            if exc.code != 400:
                evil_failed.append(name)
        except Exception:
            pass

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} clean modified/rejected via web: {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} evil bypassed via web: {', '.join(evil_failed)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_randomized_web_validation_through_nginx_and_backend():
    rng = random.SystemRandom()
    for value in rng.sample(VALID_CASES, 25):
        expected = subprocess.check_output(["/app/legacy_calc", value]).strip()
        for url in (DIRECT_URL, URL):
            with post(url, value.encode()) as response:
                assert response.status == 200
                assert response.read().strip() == expected, "service returned the wrong calculation result"

    for value in rng.sample(INVALID_CASES, 25):
        for url in (DIRECT_URL, URL):
            with pytest.raises(urllib.error.HTTPError) as raised:
                post(url, value.encode())
            assert raised.value.code == 400, f"invalid expression returned {raised.value.code}, not 400"


def test_service_executes_legacy_calculator_for_result():
    challenge = random.choice(VALID_CASES)
    token = "verified-" + secrets.token_hex(16)
    legacy = "/app/legacy_calc"
    backup = "/app/legacy_calc.verifier-backup"
    assert not os.path.exists(backup), f"temporary verifier path already exists: {backup}"
    original_mode = stat.S_IMODE(os.stat(legacy).st_mode)
    os.replace(legacy, backup)
    try:
        script = (
            "#!/usr/bin/python3\n"
            "import sys\n"
            f"expected = {json.dumps(challenge)}\n"
            f"token = {json.dumps(token)}\n"
            "print(token if len(sys.argv) == 2 and sys.argv[1] == expected else 'wrong-argument')\n"
        )
        with open(legacy, "w") as handle:
            handle.write(script)
        os.chmod(legacy, 0o755)
        with post(URL, challenge.encode()) as response:
            assert response.status == 200
            assert response.read().strip() == token.encode(), \
                "web service did not execute /app/legacy_calc with the submitted expression"
    finally:
        try:
            os.unlink(legacy)
        except FileNotFoundError:
            pass
        os.replace(backup, legacy)
        os.chmod(legacy, original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
