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

# Stop any server left by the agent so the submitted server script itself is tested.
pkill -f '[./]app/server.sh' 2>/dev/null || true
sleep 0.2

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import subprocess
import time
import uuid

import pytest
import requests

BINARY = "/app/vendored/deptool/deptool"
SOURCE_DIR = "/app/vendored/deptool"
SERVER = "/app/server.sh"
LOG = "/tmp/deptool-invocations.log"
REAL_BINARY = "/app/vendored/deptool/deptool.verifier-real"


def listener_pids(port=8080):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
        except OSError:
            pass
    return pids


def kill_listeners():
    for _ in range(5):
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.1)


def wait_for_listener(timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_pids():
            return
        time.sleep(0.05)
    pytest.fail("The submitted /app/server.sh did not listen on 127.0.0.1:8080")


def next_second():
    now = time.time()
    time.sleep(max(0, int(now) + 1.03 - now))


def run_tool(path, value):
    result = subprocess.run([path, value], text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=3)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def test_deptool_compiled_and_makefile_fixed():
    # Preserve the original existence and executable assertions.
    assert os.path.isfile(BINARY), f"The compiled binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"The compiled binary {BINARY} is not executable."

    oracle = "/tmp/deptool-oracle"
    compiled = subprocess.run(
        ["gcc", "-o", oracle, os.path.join(SOURCE_DIR, "main.c")],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert compiled.returncode == 0, f"Could not compile the provided source: {compiled.stderr}"

    # Remove the existing artifact and require the repaired Makefile to recreate it.
    os.unlink(BINARY)
    built = subprocess.run(
        ["make", "BUILD_ENV=mobile"], cwd=SOURCE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15
    )
    assert built.returncode == 0, f"The repaired Makefile failed to build deptool:\n{built.stdout}"
    assert os.path.isfile(BINARY), f"The Makefile did not recreate {BINARY}."
    assert os.access(BINARY, os.X_OK), f"The rebuilt binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "deptool is not a compiled ELF executable"

    samples = ["src/App.java"] + [f"src/{uuid.uuid4().hex}.java" for _ in range(4)]
    for sample in samples:
        expected = run_tool(oracle, sample)
        actual = run_tool(BINARY, sample)
        assert actual == expected, f"deptool returned the wrong result for {sample!r}"
    assert "//app:main" in run_tool(BINARY, "src/App.java")


def test_server_script_exists():
    # Preserve the original server artifact assertions.
    assert os.path.isfile(SERVER), f"The server script {SERVER} does not exist."
    assert os.access(SERVER, os.X_OK), f"The server script {SERVER} is not executable."
    with open(SERVER, errors="replace") as f:
        script = f.read()
    active = "\n".join(line.split("#", 1)[0] for line in script.splitlines())
    assert not re.search(r"(^|[;&|\s])(python(?:3)?|node(?:js)?)(?=\s|$)", active), \
        "server.sh must be implemented in Bash rather than Python or Node.js"


def test_http_server_resolve_and_rate_limit():
    kill_listeners()
    if os.path.exists(LOG):
        os.unlink(LOG)

    # Interpose a logging executable. A genuine server must invoke deptool with
    # each accepted JSON file value instead of returning canned responses.
    os.rename(BINARY, REAL_BINARY)
    with open(BINARY, "w") as f:
        f.write("#!/bin/bash\nprintf '%s\\n' \"$1\" >> /tmp/deptool-invocations.log\n"
                "exec /app/vendored/deptool/deptool.verifier-real \"$@\"\n")
    os.chmod(BINARY, 0o755)

    server_proc = None
    try:
        server_proc = subprocess.Popen(
            ["/bin/bash", SERVER], cwd=SOURCE_DIR,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        wait_for_listener()
        url = "http://127.0.0.1:8080/resolve"
        random_one = f"src/{uuid.uuid4().hex}.java"
        random_two = f"lib/{uuid.uuid4().hex}.kt"

        # Use a fresh fixed-second window and non-fixed inputs. The first two
        # requests must resolve through deptool and the third must be rejected.
        next_second()
        response1 = requests.post(url, json={"file": random_one}, timeout=2)
        response2 = requests.post(url, json={"file": "src/App.java"}, timeout=2)
        response3 = requests.post(url, json={"file": random_two}, timeout=2)

        assert response1.status_code == 200, f"Expected HTTP 200, got {response1.status_code}"
        assert response1.text.strip() == run_tool(REAL_BINARY, random_one)
        assert response2.status_code == 200, f"Expected HTTP 200, got {response2.status_code}"
        assert "//app:main" in response2.text
        assert response2.text.strip() == run_tool(REAL_BINARY, "src/App.java")
        assert response3.status_code == 429, \
            f"Expected HTTP 429 Too Many Requests for the third request, got {response3.status_code}"

        with open(LOG) as f:
            calls = f.read().splitlines()
        assert calls == [random_one, "src/App.java"], \
            f"Expected exactly the two accepted requests to invoke deptool, got {calls}"

        # The rejected input must work in a later second, proving this is a
        # per-second limiter rather than a hard-coded three-response sequence.
        next_second()
        response4 = requests.post(url, json={"file": random_two}, timeout=2)
        assert response4.status_code == 200
        assert response4.text.strip() == run_tool(REAL_BINARY, random_two)
        with open(LOG) as f:
            calls = f.read().splitlines()
        assert calls[-1] == random_two

        # The resolver must validate both the HTTP method and route.
        next_second()
        wrong_method = requests.get(url, timeout=2)
        assert wrong_method.status_code not in (200, 429), \
            "GET /resolve must not be handled as a valid resolution request"
        wrong_route = requests.post("http://127.0.0.1:8080/not-resolve",
                                    json={"file": random_one}, timeout=2)
        assert wrong_route.status_code not in (200, 429), \
            "POST requests to routes other than /resolve must be rejected"
    finally:
        if server_proc is not None:
            try:
                os.killpg(server_proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        kill_listeners()
        if os.path.exists(REAL_BINARY):
            if os.path.exists(BINARY):
                os.unlink(BINARY)
            os.rename(REAL_BINARY, BINARY)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
