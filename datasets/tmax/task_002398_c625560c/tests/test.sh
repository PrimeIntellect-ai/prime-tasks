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

if (
    set -e

    # The agent must have left a native compiled service listening, not an
    # interpreter running the legacy Python implementation.
    old_pid=$(python3 - <<'PY'
import glob
import os
import sys

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[3] == "0A":
                    if int(fields[1].rsplit(":", 1)[1], 16) == 9090:
                        inodes.add(fields[9])
    except OSError:
        pass

for proc in glob.glob("/proc/[0-9]*"):
    try:
        for fd in glob.glob(proc + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pid = int(proc.rsplit("/", 1)[1])
                exe = os.path.realpath(proc + "/exe")
                with open(proc + "/exe", "rb") as f:
                    assert f.read(4) == b"\x7fELF", "listener is not a native executable"
                base = os.path.basename(exe).lower()
                cmdline = open(proc + "/cmdline", "rb").read().replace(b"\0", b" ").lower()
                forbidden = ("python", "pypy", "bash", "dash", "node", "perl", "ruby")
                assert not any(name in base for name in forbidden), (
                    f"listener is an interpreter: {exe}"
                )
                assert b"/app/legacy/reference.py" not in cmdline, (
                    "listener directly runs the legacy reference implementation"
                )
                print(pid)
                sys.exit(0)
    except (OSError, AssertionError) as e:
        if isinstance(e, AssertionError):
            print(str(e), file=sys.stderr)
            sys.exit(1)

print("no process is listening on port 9090", file=sys.stderr)
sys.exit(1)
PY
    )

    test -f /app/vendored/zlib-1.3.1/Makefile
    ! grep -q -- '-DBROKEN_SYNTAX_ERROR_INJECTED_BY_CONTRIBUTOR' /app/vendored/zlib-1.3.1/Makefile
    test -f /app/vendored/zlib-1.3.1/libz.a
    ar t /app/vendored/zlib-1.3.1/libz.a | grep -q .

    # Rebuild the submitted C++ sources against the exact vendored archive.
    # The link map also proves that an object from that archive was actually
    # selected, rather than the archive merely being named on the command line.
    g++ -std=c++17 -O2 \
        -I/app/vendored/zlib-1.3.1 \
        /app/src/server.cpp /app/src/fingerprint.cpp \
        /app/vendored/zlib-1.3.1/libz.a \
        -Wl,-Map,/tmp/verifier_server.map \
        -o /tmp/verifier_cpp_server
    grep -Fq '/app/vendored/zlib-1.3.1/libz.a(' /tmp/verifier_server.map
    test "$(head -c 4 /tmp/verifier_cpp_server | od -An -tx1 | tr -d ' \n')" = "7f454c46"

    # Stop the submitted listener and exercise a fresh executable built from
    # the submitted C++ implementation, preventing a Python wrapper from
    # satisfying the behavioral checks.
    kill "$old_pid" 2>/dev/null || true
    for _ in $(seq 1 30); do
        [ ! -e "/proc/$old_pid" ] && break
        sleep 0.1
    done
    if [ -e "/proc/$old_pid" ]; then
        kill -9 "$old_pid" 2>/dev/null || true
        sleep 0.2
    fi

    /tmp/verifier_cpp_server >/tmp/verifier_cpp_server.log 2>&1 &
    verified_pid=$!
    ready=0
    for _ in $(seq 1 30); do
        if python3 - <<'PY'
import socket
s = socket.socket()
s.settimeout(0.2)
try:
    s.connect(("127.0.0.1", 9090))
finally:
    s.close()
PY
        then
            ready=1
            break
        fi
        kill -0 "$verified_pid" 2>/dev/null || break
        sleep 0.1
    done
    test "$ready" = 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import zlib
import random
import requests
import pytest

def compute_expected_fingerprint(data: bytes) -> str:
    crc = zlib.crc32(data) & 0xFFFFFFFF
    mod = 1000000007
    val = 0
    for b in data:
        val = (val * crc + b) % mod
    return f"{crc:08x}-{val:08x}"

def test_zlib_makefile_fixed():
    makefile_path = "/app/vendored/zlib-1.3.1/Makefile"
    assert os.path.exists(makefile_path), f"Makefile not found at {makefile_path}"
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-DBROKEN_SYNTAX_ERROR_INJECTED_BY_CONTRIBUTOR" not in content, (
        "The Makefile still contains the injected broken syntax error flag."
    )

def test_zlib_compiled():
    libz_path = "/app/vendored/zlib-1.3.1/libz.a"
    assert os.path.exists(libz_path), f"Compiled library not found at {libz_path}. Did you compile zlib?"

def test_submission_is_not_reference_file():
    with open("/app/src/fingerprint.cpp", "rb") as submitted:
        submitted_bytes = submitted.read()
    with open("/app/legacy/reference.py", "rb") as reference:
        reference_bytes = reference.read()
    assert submitted_bytes != reference_bytes

@pytest.mark.parametrize("payload_size", [0, 5, 1024, 5000])
def test_server_compute_endpoint(payload_size):
    if payload_size == 0:
        data = b""
    else:
        data = bytes(random.choices(range(256), k=payload_size))

    expected_fingerprint = compute_expected_fingerprint(data)
    url = "http://127.0.0.1:9090/compute"
    try:
        response = requests.post(url, data=data, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    actual_fingerprint = response.text.strip()
    assert actual_fingerprint == expected_fingerprint, (
        f"Fingerprint mismatch for payload of size {payload_size}.\n"
        f"Expected: {expected_fingerprint}\n"
        f"Actual:   {actual_fingerprint}"
    )

def test_server_specific_payloads():
    payloads = [
        b"hello world",
        b"OpenAI",
        b"\x00\x01\x02\x03\x04\x05",
        b"A" * 100
    ]

    url = "http://127.0.0.1:9090/compute"
    for data in payloads:
        expected = compute_expected_fingerprint(data)
        try:
            response = requests.post(url, data=data, timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to the server at {url}: {e}")

        assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
        actual = response.text.strip()
        assert actual == expected, (
            f"Fingerprint mismatch for payload {data!r}.\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}"
        )
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
