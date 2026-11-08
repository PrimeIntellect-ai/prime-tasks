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
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import string
import subprocess
import time

import pytest
import requests

APP = "/home/user/app"
LIB = os.path.join(APP, "libtoken.so")


def run_checked(cmd, **kwargs):
    result = subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, **kwargs)
    assert result.returncode == 0, result.stdout
    return result


@pytest.fixture(scope="session", autouse=True)
def build_check_and_restart_services():
    # A clean build must work, proving the Makefile dependency cycle is gone.
    run_checked(["make", "clean"], cwd=APP, timeout=15)
    run_checked(["make"], cwd=APP, timeout=30)
    assert os.path.isfile(LIB), "libtoken.so was not produced by a clean make"

    # Compile the submitted C sources with AddressSanitizer and exercise the
    # vulnerable boundary as well as substantially oversized inputs.
    harness = r'''
#include <stdlib.h>
#include <string.h>
int verify_token(const char *serialized_data);

int main(void) {
    int r = verify_token("");
    if (r != 0) return 10;
    r = verify_token("abc");
    if (r != 1) return 11;

    const size_t sizes[] = {16, 17, 64, 4096, 1048576};
    for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); ++i) {
        char *s = malloc(sizes[i] + 1);
        if (!s) return 12;
        memset(s, 'A' + (int)i, sizes[i]);
        s[sizes[i]] = '\0';
        r = verify_token(s);
        free(s);
        if (r != 0 && r != 1) return 13;
    }
    return 0;
}
'''
    with open("/tmp/token_asan_harness.c", "w") as f:
        f.write(harness)
    run_checked([
        "gcc", "-O0", "-g", "-fno-omit-frame-pointer",
        "-fsanitize=address", "-o", "/tmp/token_asan_harness",
        "/tmp/token_asan_harness.c", os.path.join(APP, "src/token.c"),
        os.path.join(APP, "src/crypto.c")
    ], timeout=30)
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
    run_checked(["/tmp/token_asan_harness"], env=env, timeout=15)

    # Load and invoke the artifact produced by make in a child process, so a
    # malformed or crashing shared object fails verification cleanly.
    probe = r'''
import ctypes, json, sys
lib = ctypes.CDLL("/home/user/app/libtoken.so")
fn = lib.verify_token
fn.argtypes = [ctypes.c_char_p]
fn.restype = ctypes.c_int
values = json.load(sys.stdin)
print(json.dumps([fn(v.encode("utf-8")) for v in values]))
'''
    with open("/tmp/probe_libtoken.py", "w") as f:
        f.write(probe)

    # Restart through the required wrapper only after the fresh library exists.
    result = subprocess.run(
        ["bash", os.path.join(APP, "start_services.sh")],
        cwd=APP, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        timeout=10
    )
    assert result.returncode == 0, "start_services.sh failed"

    deadline = time.time() + 10
    while time.time() < deadline:
        try:
            a = requests.post("http://127.0.0.1:8080/verify",
                              json={"token": "startup"}, timeout=0.5)
            m = requests.get("http://127.0.0.1:8081/stats", timeout=0.5)
            if a.status_code == 200 and m.status_code == 200:
                break
        except requests.RequestException:
            pass
        time.sleep(0.2)
    else:
        pytest.fail("Services did not start through start_services.sh")


def library_results(tokens):
    result = subprocess.run(
        ["python3", "/tmp/probe_libtoken.py"],
        input=json.dumps(tokens), text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, "libtoken invocation failed:\n" + result.stderr
    values = json.loads(result.stdout)
    assert len(values) == len(tokens)
    assert all(v in (0, 1) for v in values), "verify_token must return 0 or 1"
    return values


def matching_processes(script_path):
    matches = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            if script_path in args:
                matches.append(int(name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return matches


def test_libtoken_built():
    """Ensure the shared object library was built successfully."""
    assert os.path.exists(LIB), "libtoken.so was not built. Did you fix the Makefile and run make?"
    assert os.path.isfile(LIB), "libtoken.so is not a regular file"
    with open(LIB, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libtoken.so is not an ELF shared object"
    lib = ctypes.CDLL(LIB)
    assert getattr(lib, "verify_token", None) is not None


def test_api_uses_built_library():
    alphabet = string.ascii_letters + string.digits
    tokens = [
        "",
        "".join(random.SystemRandom().choice(alphabet) for _ in range(9)),
        "".join(random.SystemRandom().choice(alphabet) for _ in range(37)),
        "".join(random.SystemRandom().choice(alphabet) for _ in range(4097)),
    ]
    results = library_results(tokens)
    assert results[0] == 0
    assert results[1] == 1

    for token, native_result in zip(tokens, results):
        response = requests.post("http://127.0.0.1:8080/verify",
                                 json={"token": token}, timeout=5)
        assert response.status_code == 200, response.text
        data = response.json()
        assert data == {"result": "verified" if native_result else "failed"}

    api_pids = matching_processes("/home/user/app/api.py")
    assert api_pids, "api.py is not the process serving the API"
    mapped = False
    for pid in api_pids:
        try:
            with open(f"/proc/{pid}/maps", "r") as f:
                if any("/home/user/app/libtoken.so" in line for line in f):
                    mapped = True
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert mapped, "The running api.py process has not loaded libtoken.so"


def test_api_verify_no_crash():
    """Retain the original long-token HTTP assertion."""
    url = "http://127.0.0.1:8080/verify"
    payload = {"token": "A_VERY_LONG_USERNAME_THAT_EXCEEDS_SIXTEEN_BYTES_AND_THEN_SOME"}
    try:
        response = requests.post(url, json=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("API service on port 8080 is not reachable or crashed. The buffer overflow might not be fixed, or the service wasn't started.")
    except requests.exceptions.Timeout:
        pytest.fail("API service on port 8080 timed out.")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")
    assert "result" in data, "Response JSON missing 'result' key."
    assert data["result"] in ["verified", "failed"], f"Unexpected result value: {data['result']}"


def test_metrics_service_reachable():
    """Ensure the metrics service is running and reachable."""
    url = "http://127.0.0.1:8081/stats"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Metrics service on port 8081 is not reachable. Did you start the services?")
    except requests.exceptions.Timeout:
        pytest.fail("Metrics service on port 8081 timed out.")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}."
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")
    assert "reqs" in data, "Response JSON missing 'reqs' key."
    assert matching_processes("/home/user/app/metrics.py"), "metrics.py is not running"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
