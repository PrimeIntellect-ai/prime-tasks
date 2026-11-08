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

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import re
import shutil
import stat
import subprocess
import time
import uuid

import pytest
import requests

URL = "http://127.0.0.1:8080/api/v1/math/poly"
SERVER = "/home/user/server.sh"
LIBRARY = "/home/user/liblicense.so"
BINARY = "/app/bin/polycalc"


def post(x, y):
    try:
        return requests.post(URL, json={"x": x, "y": y}, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Request to {URL} failed: {exc}")


def assert_success_response(response, expected, x, y):
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "status" in data, f"Missing 'status' in response: {data}"
    assert data["status"] == "success", (
        f"Expected status 'success', got {data['status']}"
    )
    assert "result" in data, f"Missing 'result' in response: {data}"
    assert data["result"] == expected, (
        f"For x={x}, y={y}, expected result {expected}, got {data['result']}"
    )


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    found = set()
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
                    found.add(int(name))
                    break
        except OSError:
            continue
    return found


def process_chain(pid):
    seen = set()
    while pid > 1 and pid not in seen:
        seen.add(pid)
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as handle:
                cmdline = handle.read().replace(b"\0", b" ").decode(errors="replace")
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
            with open(f"/proc/{pid}/stat") as handle:
                stat_fields = handle.read().split()
            ppid = int(stat_fields[3])
        except (OSError, ValueError, IndexError):
            break
        yield pid, exe, cmdline
        pid = ppid


def test_final_state():
    assert os.path.isfile(SERVER), f"Missing required Bash server: {SERVER}"
    assert os.path.isfile(LIBRARY), f"Missing required license library: {LIBRARY}"
    assert os.path.isfile(BINARY), f"Missing proprietary engine: {BINARY}"

    with open(SERVER, "r", errors="replace") as handle:
        server_source = handle.read()
    first_line = server_source.splitlines()[0] if server_source.splitlines() else ""
    assert re.search(r"^#!.*(?:/|\b)bash\b", first_line), "server.sh must be a Bash script"
    assert re.search(r"(?:^|[;\n]\s*|\bexport\s+)LD_LIBRARY_PATH\s*=", server_source), (
        "server.sh must configure LD_LIBRARY_PATH"
    )
    assert "/home/user" in server_source, (
        "server.sh must make /home/user available through LD_LIBRARY_PATH"
    )

    readelf = subprocess.run(
        ["readelf", "-h", LIBRARY], text=True, capture_output=True
    )
    assert readelf.returncode == 0 and re.search(r"Type:\s+DYN", readelf.stdout), (
        "liblicense.so is not a valid ELF shared object"
    )
    symbols = subprocess.run(
        ["nm", "-D", LIBRARY], text=True, capture_output=True
    )
    assert symbols.returncode == 0
    assert re.search(r"\bverify_license_key\b", symbols.stdout), (
        "liblicense.so does not export verify_license_key"
    )

    license_lib = ctypes.CDLL(LIBRARY)
    verify = license_lib.verify_license_key
    verify.restype = ctypes.c_int
    verify.argtypes = []
    assert verify() == 1, "verify_license_key() must return 1"

    engine_env = os.environ.copy()
    engine_env["LD_LIBRARY_PATH"] = "/home/user"
    for x, y in ((2, 3), (-4, 7), (11, -5)):
        run = subprocess.run(
            [BINARY, str(x), str(y)], env=engine_env,
            text=True, capture_output=True, timeout=5
        )
        assert run.returncode == 0, f"polycalc failed: {run.stderr}"
        assert run.stdout.strip() == str(3 * x * x + 2 * y + 1), (
            f"polycalc returned an incorrect result for x={x}, y={y}"
        )

    time.sleep(1)

    # Preserve the original behavioral assertions on multiple random requests.
    for _ in range(5):
        x = random.randint(1, 20)
        y = random.randint(1, 20)
        expected = 3 * (x ** 2) + 2 * y + 1
        assert_success_response(post(x, y), expected, x, y)

    listeners = listener_pids(8080)
    assert listeners, "No process is listening on 127.0.0.1:8080"
    bash_server_found = False
    for pid in listeners:
        for _, exe, cmdline in process_chain(pid):
            if exe.startswith("bash") and SERVER in cmdline:
                bash_server_found = True
                break
    assert bash_server_found, (
        "The listener is not running from /home/user/server.sh under Bash"
    )

    token = uuid.uuid4().hex
    lib_backup = f"/home/user/.liblicense.backup.{token}.so"
    lib_probe = f"/home/user/.liblicense.probe.{token}.so"
    lib_source = f"/tmp/license_probe_{token}.c"
    lib_log = f"/tmp/license_probe_{token}.log"

    with open(lib_source, "w") as handle:
        handle.write(
            "#include <fcntl.h>\n"
            "#include <unistd.h>\n"
            "int verify_license_key(void) {\n"
            f"  int fd = open(\"{lib_log}\", O_WRONLY|O_CREAT|O_APPEND, 0666);\n"
            "  if (fd >= 0) { write(fd, \"called\\n\", 7); close(fd); }\n"
            "  return 1;\n"
            "}\n"
        )
    compile_probe = subprocess.run(
        ["gcc", "-shared", "-fPIC", lib_source, "-o", lib_probe],
        text=True, capture_output=True
    )
    assert compile_probe.returncode == 0, compile_probe.stderr

    os.replace(LIBRARY, lib_backup)
    os.replace(lib_probe, LIBRARY)
    try:
        x, y = random.randint(21, 50), random.randint(21, 50)
        expected = 3 * x * x + 2 * y + 1
        assert_success_response(post(x, y), expected, x, y)
        assert os.path.exists(lib_log), (
            "HTTP request did not load /home/user/liblicense.so through polycalc"
        )
        with open(lib_log) as handle:
            assert "called" in handle.read(), (
                "verify_license_key from /home/user/liblicense.so was not invoked"
            )
    finally:
        if os.path.lexists(LIBRARY):
            os.unlink(LIBRARY)
        os.replace(lib_backup, LIBRARY)
        for path in (lib_probe, lib_source, lib_log):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

    # Replace only the engine pathname with a sentinel implementation. The API
    # must pass the supplied arguments to it and return its output, proving that
    # it does not recompute the polynomial in the HTTP layer.
    binary_backup = f"/app/bin/.polycalc.backup.{token}"
    binary_log = f"/tmp/polycalc_probe_{token}.log"
    sentinel = random.randint(1500000000, 1900000000)
    os.replace(BINARY, binary_backup)
    try:
        with open(BINARY, "w") as handle:
            handle.write("#!/bin/bash\n")
            handle.write(f"printf '%s %s\\n' \"$1\" \"$2\" >> {binary_log}\n")
            handle.write(f"printf '%s\\n' '{sentinel}'\n")
        os.chmod(BINARY, 0o755)

        x, y = random.randint(51, 90), random.randint(51, 90)
        assert_success_response(post(x, y), sentinel, x, y)
        assert os.path.exists(binary_log), "The server did not invoke /app/bin/polycalc"
        with open(binary_log) as handle:
            calls = [line.strip() for line in handle if line.strip()]
        assert f"{x} {y}" in calls, (
            "The server did not pass the request's x and y arguments to polycalc"
        )
    finally:
        if os.path.lexists(BINARY):
            os.unlink(BINARY)
        os.replace(binary_backup, BINARY)
        try:
            os.unlink(binary_log)
        except FileNotFoundError:
            pass
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
