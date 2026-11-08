#!/bin/bash
mkdir -p /logs/verifier
printf '0\n' > /logs/verifier/reward.txt
set -e

WORKDIR="$(mktemp -d /tmp/verifier.XXXXXX)"
LIB="/home/user/legacy_lib/libcustom_hash.so"
SRC="/home/user/legacy_lib/custom_hash.c"
LIB_BACKUP="$WORKDIR/libcustom_hash.so.orig"
SRC_BACKUP="$WORKDIR/custom_hash.c.orig"
SERVER_PID=""

cleanup() {
    if [ -f "$LIB_BACKUP" ]; then
        mv -f "$LIB_BACKUP" "$LIB"
    fi
    if [ -f "$SRC_BACKUP" ]; then
        mv -f "$SRC_BACKUP" "$SRC"
    fi
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

# Preserve the submitted artifacts before installing an instrumented equivalent.
test -f "$LIB"
test -f "$SRC"
cp -a "$LIB" "$LIB_BACKUP"
cp -a "$SRC" "$SRC_BACKUP"

# Stop the submitted background instance so it must load the library afresh.
pkill -f '[s]erver.py' 2>/dev/null || true
if command -v fuser >/dev/null 2>&1; then
    fuser -k 8765/tcp 2>/dev/null || true
fi
sleep 1

# This implementation has the legacy function's exact behavior, but records the
# actual strings passed to compute_hash. This verifies calls through the shared
# library rather than merely accepting independently computed answers.
cat > "$SRC" <<'C_EOF'
#include <string.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>

int compute_hash(const char* input) {
    const char *marker = getenv("VERIFY_HASH_MARKER");
    if (marker != NULL && input != NULL) {
        int fd = open(marker, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) {
            write(fd, input, strlen(input));
            write(fd, "\n", 1);
            close(fd);
        }
    }
    int sum = 0;
    if (input != NULL) {
        for (size_t i = 0; i < strlen(input); i++) {
            sum += (unsigned char)input[i];
        }
    }
    return sum % 256;
}
C_EOF

gcc -shared -fPIC -o "$LIB" "$SRC"
MARKER="$WORKDIR/hash_calls.log"
: > "$MARKER"
VERIFY_HASH_MARKER="$MARKER" nohup python3 /home/user/server.py >"$WORKDIR/server.log" 2>&1 &
SERVER_PID=$!
export VERIFY_HASH_MARKER="$MARKER"

# Wait for the required listener.
python3 - <<'PY'
import socket, time
for _ in range(100):
    try:
        with socket.create_connection(("127.0.0.1", 8765), timeout=0.2):
            break
    except OSError:
        time.sleep(0.1)
else:
    raise SystemExit("Server did not start on 127.0.0.1:8765")
PY

cat > "$WORKDIR/test_final_state.py" <<'PY_EOF'
import asyncio
import collections
import ctypes
import json
import os
import random
import secrets
import string

import pytest

TOKEN = "X7B9K2M4P1Q8"
URI = "ws://127.0.0.1:8765"
MARKER = os.environ["VERIFY_HASH_MARKER"]
ALPHABET = string.ascii_letters + string.digits


def compute_expected_hash(filename):
    return sum(ord(c) for c in filename) % 256


def make_filename():
    stem = "".join(secrets.choice(ALPHABET) for _ in range(random.randint(5, 18)))
    return stem + secrets.choice([".txt", ".log", ".doc", ".bin", ".data"])


# Fresh, unpredictable cases prevent a server from hardcoding the audited list.
CASES = []
for count in (1, 3, 5, 7, 9):
    case = [make_filename() for _ in range(count)]
    random.shuffle(case)
    CASES.append(case)


def test_agent_files_exist():
    assert os.path.isfile("/home/user/server.py"), "Server script /home/user/server.py is missing."
    assert os.path.isfile("/home/user/tests/test_server.py"), "Test script /home/user/tests/test_server.py is missing."

    lib_dir = "/home/user/legacy_lib"
    so_files = [f for f in os.listdir(lib_dir) if f.endswith(".so")]
    assert len(so_files) > 0, "No compiled shared library (.so) found in /home/user/legacy_lib/"


def test_shared_library_exports_correct_function():
    lib_path = "/home/user/legacy_lib/libcustom_hash.so"
    assert os.path.isfile(lib_path)
    lib = ctypes.CDLL(lib_path)
    fn = lib.compute_hash
    fn.argtypes = [ctypes.c_char_p]
    fn.restype = ctypes.c_int
    for value in ("", "independent-check.txt", make_filename()):
        assert fn(value.encode("ascii")) == compute_expected_hash(value)


async def assert_bad_auth_is_closed():
    import websockets
    from websockets.exceptions import ConnectionClosed

    bad = "".join(secrets.choice(ALPHABET) for _ in range(12))
    if bad == TOKEN:
        bad = "0" + bad[1:]
    async with websockets.connect(URI, ping_timeout=5) as websocket:
        await websocket.send(json.dumps({"type": "auth", "token": bad}))
        deadline = asyncio.get_running_loop().time() + 3.0
        while True:
            remaining = deadline - asyncio.get_running_loop().time()
            assert remaining > 0, "Connection remained open after incorrect authentication."
            try:
                await asyncio.wait_for(websocket.recv(), timeout=remaining)
            except ConnectionClosed:
                return


async def run_organize_case(input_files):
    import websockets

    async with websockets.connect(URI, ping_timeout=5) as websocket:
        auth_msg = {"type": "auth", "token": TOKEN}
        await websocket.send(json.dumps(auth_msg))
        await asyncio.sleep(0.05)

        if hasattr(websocket, "open"):
            assert websocket.open, "WebSocket connection was closed after sending correct auth token."
        else:
            state = getattr(websocket, "state", None)
            assert getattr(state, "name", "").upper() == "OPEN", \
                "WebSocket connection was closed after sending correct auth token."

        organize_msg = {"type": "organize", "files": input_files}
        await websocket.send(json.dumps(organize_msg))
        response_str = await asyncio.wait_for(websocket.recv(), timeout=5.0)
        response = json.loads(response_str)

        assert response.get("type") == "result", \
            f"Expected response type 'result', got: {response.get('type')}"
        expected_sorted = sorted(input_files)
        assert response.get("sorted_files") == expected_sorted, \
            f"Expected sorted files {expected_sorted}, got {response.get('sorted_files')}"
        expected_hashes = [compute_expected_hash(f) for f in expected_sorted]
        assert response.get("hashes") == expected_hashes, \
            f"Expected hashes {expected_hashes}, got {response.get('hashes')}"


def test_websocket_server_protocol_and_authentication():
    try:
        import websockets  # noqa: F401
    except ImportError:
        pytest.fail("websockets library is not installed, cannot test WebSocket server.")

    async def scenario():
        await assert_bad_auth_is_closed()
        for case in CASES:
            await run_organize_case(case)

    try:
        asyncio.run(scenario())
    except ConnectionRefusedError:
        pytest.fail("Connection refused. The WebSocket server is not running on 127.0.0.1:8765.")
    except asyncio.TimeoutError:
        pytest.fail("Timed out waiting for a response from the WebSocket server.")


def test_compute_hash_was_called_for_each_requested_filename():
    with open(MARKER, "r", encoding="utf-8") as f:
        observed = collections.Counter(line.rstrip("\n") for line in f)
    requested = collections.Counter(name for case in CASES for name in case)
    missing = requested - observed
    assert not missing, \
        f"compute_hash was not invoked through the shared library for: {dict(missing)}"
PY_EOF

if python3 -m pytest "$WORKDIR/test_final_state.py" -x --tb=short 2>&1; then
    printf '1\n' > /logs/verifier/reward.txt
fi
