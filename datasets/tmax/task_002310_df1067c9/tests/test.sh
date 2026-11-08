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
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import re
import signal
import subprocess
import time

import pytest
import requests

WORKSPACE_DIR = "/home/user/workspace"
NGINX_URL = "http://127.0.0.1:8080/api/diff"
BACKEND_URL = "http://127.0.0.1:9090/internal/diff"
AUTH_TOKEN = "super-secret-token"


def expected_diff(a, b):
    return ",".join(str(x) for x in sorted(set(a) ^ set(b)))


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_port = int(fields[1].split(":")[1], 16)
                    if local_port == port and fields[3] == "0A":
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def stop_services():
    subprocess.run(
        ["su", "-s", "/bin/bash", "user", "-c",
         f"nginx -c {WORKSPACE_DIR}/nginx.conf -s quit"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5,
        check=False,
    )
    time.sleep(0.5)
    for pid in listener_pids(8080) | listener_pids(9090):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(1)
    for pid in listener_pids(8080) | listener_pids(9090):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_services(proc):
    deadline = time.time() + 15
    last_error = None
    while time.time() < deadline:
        if proc.poll() not in (None, 0):
            pytest.fail(f"start.sh exited with status {proc.returncode}")
        try:
            backend = requests.post(
                BACKEND_URL, json={"a": "91,92", "b": "92,93"}, timeout=0.5
            )
            proxy = requests.post(
                NGINX_URL,
                json={"a": "81,82", "b": "82,83"},
                headers={"Authorization": f"Bearer {AUTH_TOKEN}"},
                timeout=0.5,
            )
            if (backend.status_code == 200 and backend.text.strip() == "91,93" and
                    proxy.status_code == 200 and proxy.text.strip() == "81,83"):
                return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.25)
    pytest.fail(f"Services did not become ready: {last_error}")


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_start():
    required = ["plugin_diff.cpp", "server.cpp", "httplib.h", "build.sh", "start.sh", "nginx.conf"]
    for name in required:
        assert os.path.isfile(os.path.join(WORKSPACE_DIR, name)), f"{name} is missing."

    stop_services()
    for name in ("libdiffplugin.so", "server"):
        try:
            os.remove(os.path.join(WORKSPACE_DIR, name))
        except FileNotFoundError:
            pass

    build = subprocess.run(
        ["su", "-s", "/bin/bash", "user", "-c",
         f"cd {WORKSPACE_DIR} && bash ./build.sh"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
    )
    assert build.returncode == 0, f"build.sh failed:\n{build.stdout}"
    assert os.path.isfile(os.path.join(WORKSPACE_DIR, "libdiffplugin.so")), \
        "build.sh did not create libdiffplugin.so"

    proc = subprocess.Popen(
        ["su", "-s", "/bin/bash", "user", "-c",
         f"cd {WORKSPACE_DIR} && bash ./start.sh"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    wait_for_services(proc)
    yield


def test_files_exist():
    assert os.path.exists(os.path.join(WORKSPACE_DIR, "libdiffplugin.so")), "libdiffplugin.so is missing."
    assert os.path.exists(os.path.join(WORKSPACE_DIR, "nginx.conf")), "nginx.conf is missing."


def test_artifact_types_sources_and_scripts():
    lib_path = os.path.join(WORKSPACE_DIR, "libdiffplugin.so")
    elf = subprocess.run(["readelf", "-h", lib_path], text=True,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert elf.returncode == 0 and re.search(r"Type:\s+DYN", elf.stdout), \
        "libdiffplugin.so is not an ELF shared object"
    symbols = subprocess.run(["nm", "-D", "--defined-only", lib_path], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert symbols.returncode == 0
    assert re.search(r"\bcompute_diff$", symbols.stdout, re.MULTILINE), \
        "The shared library does not export the unmangled compute_diff ABI symbol"

    with open(os.path.join(WORKSPACE_DIR, "plugin_diff.cpp"), errors="replace") as f:
        plugin_source = f.read()
    assert re.search(r'extern\s+"C"\s+void\s+compute_diff\s*\(', plugin_source), \
        "plugin_diff.cpp does not declare the required C ABI"

    httplib_path = os.path.join(WORKSPACE_DIR, "httplib.h")
    assert os.path.getsize(httplib_path) > 50000, "httplib.h is not the cpp-httplib single header"
    with open(httplib_path, errors="replace") as f:
        header_sample = f.read()
    assert "namespace httplib" in header_sample, "httplib.h does not contain cpp-httplib"

    with open(os.path.join(WORKSPACE_DIR, "server.cpp"), errors="replace") as f:
        server_source = f.read()
    assert re.search(r'#\s*include\s*[<\"]httplib\.h[>\"]', server_source), \
        "server.cpp does not include httplib.h"
    assert re.search(r'httplib\s*::\s*Server', server_source), \
        "server.cpp does not use cpp-httplib's Server"
    assert re.search(r'\bdlopen\s*\(', server_source), "server.cpp does not call dlopen"
    assert re.search(r'\bdlsym\s*\(', server_source), "server.cpp does not call dlsym"
    assert "compute_diff" in server_source, "server.cpp does not resolve compute_diff"
    assert os.path.isdir(os.path.join(WORKSPACE_DIR, "nginx_temp")), "nginx_temp is missing"


def test_plugin_abi_on_varied_inputs():
    lib = ctypes.CDLL(os.path.join(WORKSPACE_DIR, "libdiffplugin.so"))
    fn = lib.compute_diff
    fn.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_char), ctypes.c_size_t]
    fn.restype = None
    rng = random.SystemRandom()

    cases = [([5, 1, 3], [3, 2, 4]), ([-9, -1, 0, 14], [-1, 3, 14])]
    for _ in range(30):
        a = rng.sample(range(-1000000, 1000001), rng.randint(2, 35))
        b = rng.sample(range(-1000000, 1000001), rng.randint(2, 35))
        cases.append((a, b))

    for a, b in cases:
        out = ctypes.create_string_buffer(8192)
        fn(",".join(map(str, a)).encode(), ",".join(map(str, b)).encode(), out, 8192)
        actual = out.value.decode()
        assert actual == expected_diff(a, b), \
            f"compute_diff({a}, {b}) returned {actual!r}"


def test_backend_has_plugin_dynamically_loaded():
    pids = listener_pids(9090)
    assert pids, "No process is listening on backend port 9090"
    wanted = os.path.realpath(os.path.join(WORKSPACE_DIR, "libdiffplugin.so"))
    loaded = False
    for pid in pids:
        try:
            with open(f"/proc/{pid}/maps") as f:
                for line in f:
                    mapped = line.split()[-1] if len(line.split()) >= 6 else ""
                    if mapped == wanted or mapped.startswith(wanted + " "):
                        loaded = True
                        break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert loaded, "The backend listening on port 9090 has not dynamically loaded libdiffplugin.so"


def test_nginx_auth_failure():
    # Flow 1: No auth
    try:
        response = requests.post(NGINX_URL, json={"a": "1,2", "b": "2,3"}, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx at {NGINX_URL}: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"

    # Flow 1: Wrong auth
    headers = {"Authorization": "Bearer wrong-token"}
    try:
        response = requests.post(NGINX_URL, json={"a": "1,2", "b": "2,3"}, headers=headers, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx at {NGINX_URL}: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized for wrong token, got {response.status_code}"

    for value in ("Bearer super-secret-token-extra", "bearer super-secret-token"):
        response = requests.post(NGINX_URL, json={"a": "4,5", "b": "5,6"},
                                 headers={"Authorization": value}, timeout=2)
        assert response.status_code == 401, f"Authorization value {value!r} was not rejected"


def test_backend_direct():
    # Flow 2: Backend Direct
    payload = {"a": "10,20,30", "b": "20,40"}
    try:
        response = requests.post(BACKEND_URL, json=payload, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to backend at {BACKEND_URL}: {e}")

    assert response.status_code == 200, f"Expected 200 OK from backend, got {response.status_code}. Body: {response.text}"
    assert response.text.strip() == "10,30,40", f"Expected diff '10,30,40', got '{response.text.strip()}'"


def test_nginx_end_to_end_success():
    # Flow 3: End-to-End Success
    payload = {"a": "7,3,1,5", "b": "5,8,1,2"}
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    try:
        response = requests.post(NGINX_URL, json=payload, headers=headers, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx at {NGINX_URL}: {e}")

    assert response.status_code == 200, f"Expected 200 OK from Nginx, got {response.status_code}. Body: {response.text}"
    assert response.text.strip() == "2,3,7,8", f"Expected diff '2,3,7,8', got '{response.text.strip()}'"


def test_varied_backend_and_proxy_requests():
    rng = random.SystemRandom()
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    for i in range(20):
        a = rng.sample(range(-2000000, 2000001), rng.randint(3, 30))
        b = rng.sample(range(-2000000, 2000001), rng.randint(3, 30))
        payload = {"a": ",".join(map(str, a)), "b": ",".join(map(str, b))}
        expected = expected_diff(a, b)
        url = BACKEND_URL if i % 2 == 0 else NGINX_URL
        request_headers = None if i % 2 == 0 else headers
        response = requests.post(url, json=payload, headers=request_headers, timeout=3)
        assert response.status_code == 200, f"Request to {url} failed: {response.status_code} {response.text}"
        assert response.text.strip() == expected, \
            f"Wrong symmetric difference for generated payload {payload}: {response.text!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
