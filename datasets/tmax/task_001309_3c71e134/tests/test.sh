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
import base64
import ctypes
import json
import os
import random
import secrets
import signal
import subprocess
import time

import pytest
import requests

URL = "http://127.0.0.1:8080/encode"
HEADERS = {"Authorization": "Bearer migrate-token-2024"}
SO_PATH = "/app/rust_math/target/release/librust_math.so"


def expected_encoding(text):
    raw = text.encode("utf-8")
    return base64.b64encode(bytes((b * 17) % 256 for b in raw)).decode("ascii")


def wait_for_server(proc=None, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc is not None and proc.poll() is not None:
            pytest.fail("Server exited during startup")
        try:
            requests.post(URL, json={"data": "probe"}, timeout=0.3)
            return
        except requests.RequestException:
            time.sleep(0.1)
    pytest.fail("Failed to connect to the server on 127.0.0.1:8080")


def listener_pids(port=8080):
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
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
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
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def stop_server():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline and listener_pids():
        time.sleep(0.1)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    assert not listener_pids(), "Could not stop the server using port 8080"


def test_config_exists():
    config_path = "/app/config.json"
    assert os.path.exists(config_path), f"Configuration file {config_path} is missing."
    with open(config_path, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Configuration file {config_path} is not valid JSON.")
    assert config.get("environment") == "production", "Config 'environment' is not 'production'."
    assert config.get("version") == 3, "Config 'version' is not 3."


def test_rust_library_compiled():
    assert os.path.exists(SO_PATH), f"Compiled Rust library {SO_PATH} is missing. Did you build with --release?"
    with open(SO_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Release library is not an ELF shared object"


def test_cargo_bench_succeeds():
    result = subprocess.run(
        ["cargo", "bench"], cwd="/app/rust_math", stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=180
    )
    assert result.returncode == 0, "cargo bench failed:\n" + result.stdout


def test_rust_process_bytes_correctly():
    lib = ctypes.CDLL(SO_PATH)
    fn = lib.process_bytes
    fn.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint8, ctypes.c_void_p]
    fn.restype = None

    rng = random.SystemRandom()
    cases = [b"abc", bytes(range(256)), os.urandom(73)]
    for raw in cases:
        for multiplier in (0, 1, 17, 255, rng.randrange(2, 255)):
            in_buf = (ctypes.c_ubyte * len(raw)).from_buffer_copy(raw)
            out_buf = (ctypes.c_ubyte * len(raw))()
            fn(in_buf, len(raw), multiplier, out_buf)
            expected = bytes((b * multiplier) % 256 for b in raw)
            assert bytes(out_buf) == expected


def test_server_unauthorized():
    try:
        response = requests.post(URL, json={"data": "test"}, timeout=3)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the server. Is it running on 127.0.0.1:8080?")
    assert response.status_code == 401, f"Expected 401 Unauthorized for missing auth header, got {response.status_code}"

    response = requests.post(
        URL, headers={"Authorization": "Bearer wrong-token"}, json={"data": "test"}, timeout=3
    )
    assert response.status_code == 401, f"Expected 401 Unauthorized for wrong auth header, got {response.status_code}"


def test_server_encode_success():
    test_string = "test_string"
    try:
        response = requests.post(URL, headers=HEADERS, json={"data": test_string}, timeout=3)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the server. Is it running on 127.0.0.1:8080?")
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        resp_json = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Server response is not valid JSON: {response.text}")
    assert "result" in resp_json, "Response JSON missing 'result' key."
    expected = expected_encoding(test_string)
    assert resp_json["result"] == expected, f"Expected encoded result '{expected}', got '{resp_json['result']}'"


def test_server_dynamic_utf8_inputs():
    values = [
        "",
        "nul-\\u0000-byte".replace("\\u0000", "\u0000"),
        "héllø 世界 🚀 " + secrets.token_hex(8),
        secrets.token_urlsafe(37),
    ]
    for value in values:
        response = requests.post(URL, headers=HEADERS, json={"data": value}, timeout=3)
        assert response.status_code == 200, response.text
        assert response.headers.get("Content-Type", "").split(";", 1)[0] == "application/json"
        body = response.json()
        assert body.get("result") == expected_encoding(value)


def test_server_reads_config_and_calls_release_library():
    stop_server()
    backup = SO_PATH + ".verifier-backup"
    shim_dir = "/tmp/verifier_shim"
    marker = "/tmp/config-opened.marker"
    os.makedirs(shim_dir, exist_ok=True)
    if os.path.exists(marker):
        os.unlink(marker)

    with open(os.path.join(shim_dir, "shim.rs"), "w") as f:
        f.write(r'''
#[no_mangle]
pub unsafe extern "C" fn process_bytes(input: *const u8, len: usize, multiplier: u8, output: *mut u8) {
    for i in 0..len {
        *output.add(i) = (*input.add(i)).wrapping_add(multiplier).wrapping_add(73);
    }
}
''')

    with open(os.path.join(shim_dir, "sitecustomize.py"), "w") as f:
        f.write('''import os, sys
_seen = False
def _audit(event, args):
    global _seen
    if event == "open" and not _seen:
        try:
            path = os.path.abspath(os.fspath(args[0]))
        except (TypeError, ValueError):
            return
        if path == "/app/config.json":
            _seen = True
            with open(os.environ["CONFIG_AUDIT_MARKER"], "w") as out:
                out.write("opened")
sys.addaudithook(_audit)
''')

    compile_result = subprocess.run(
        ["rustc", "--crate-type", "cdylib", "-O", os.path.join(shim_dir, "shim.rs"), "-o", os.path.join(shim_dir, "librust_math.so")],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert compile_result.returncode == 0, compile_result.stdout

    os.replace(SO_PATH, backup)
    proc = None
    try:
        subprocess.run(["cp", os.path.join(shim_dir, "librust_math.so"), SO_PATH], check=True)
        env = os.environ.copy()
        env["PYTHONPATH"] = shim_dir + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        env["CONFIG_AUDIT_MARKER"] = marker
        proc = subprocess.Popen(
            ["python3", "/app/server.py"], cwd="/app", env=env,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        wait_for_server(proc)
        assert os.path.exists(marker), "server.py did not read /app/config.json during startup"

        value = "shim-" + secrets.token_hex(12) + "-é"
        response = requests.post(URL, headers=HEADERS, json={"data": value}, timeout=3)
        assert response.status_code == 200, response.text
        raw = value.encode("utf-8")
        shim_result = bytes((b + 17 + 73) % 256 for b in raw)
        expected = base64.b64encode(shim_result).decode("ascii")
        assert response.json().get("result") == expected, "Server did not call process_bytes from the release Rust library"
    finally:
        stop_server()
        if os.path.exists(backup):
            os.replace(backup, SO_PATH)
        final_proc = subprocess.Popen(
            ["python3", "/app/server.py"], cwd="/app",
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        wait_for_server(final_proc)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
