#!/bin/bash
set +e
mkdir -p /logs/verifier

verify() (
    set -e
    WS_PID=""
    BACKUP_DIR="$(mktemp -d)"
    cleanup() {
        if [ -d "$BACKUP_DIR/src" ]; then
            cp -f "$BACKUP_DIR/src/"*.c /home/user/workspace/src/ 2>/dev/null || true
        fi
        if [ -n "$WS_PID" ]; then
            kill "$WS_PID" 2>/dev/null || true
            wait "$WS_PID" 2>/dev/null || true
        fi
        rm -rf "$BACKUP_DIR"
    }
    trap cleanup EXIT

    python3 - <<'PY'
import os

workspace = "/home/user/workspace"
for name in ("builder.py", "run_test.py"):
    path = os.path.join(workspace, name)
    assert os.path.isfile(path), f"{name} is missing in /home/user/workspace/"

for name in ("modA.so", "modB.so", "modC.so", "modD.so"):
    path = os.path.join(workspace, name)
    assert os.path.isfile(path), f"Compiled library {path} is missing. Ensure builder.py compiles the C files."

result = os.path.join(workspace, "result.txt")
assert os.path.isfile(result), "result.txt is missing in /home/user/workspace/"
with open(result) as f:
    content = f.read().strip()
assert content == "70", f"Expected result.txt to contain '70', but found '{content}'."

expected_sources = {
    "modA.c": "int getA() {\n    return 10;\n}\n",
    "modB.c": "extern int getA();\nint getB() {\n    return getA() + 20;\n}\n",
    "modC.c": "extern int getA();\nint getC() {\n    return getA() + 30;\n}\n",
    "modD.c": "extern int getB();\nextern int getC();\nint getD() {\n    return getB() + getC();\n}\n",
}
for name, expected in expected_sources.items():
    with open(os.path.join(workspace, "src", name)) as f:
        assert f.read() == expected, f"Provided source file {name} was modified"
PY

    mkdir -p "$BACKUP_DIR/src"
    cp -f /home/user/workspace/src/*.c "$BACKUP_DIR/src/"

    # Replace any previously started dependency server with an instrumented one.
    pkill -f '[w]s_server.py' 2>/dev/null || true
    sleep 1
    WS_MARK="/tmp/verifier_ws_connected_$$"
    rm -f "$WS_MARK"
    cat > /tmp/verifier_ws_server.py <<'PY'
import asyncio
import json
import sys
import websockets

marker = sys.argv[1]
graph = {
    "modA": [],
    "modB": ["modA"],
    "modC": ["modA"],
    "modD": ["modB", "modC"],
}

async def handler(websocket, *args):
    with open(marker, "a") as f:
        f.write("connected\n")
    await websocket.send(json.dumps(graph))
    await websocket.wait_closed()

async def main():
    async with websockets.serve(handler, "localhost", 8765):
        await asyncio.Future()

asyncio.run(main())
PY
    python3 /tmp/verifier_ws_server.py "$WS_MARK" &
    WS_PID=$!
    sleep 1
    kill -0 "$WS_PID"

    # Change the source constants so a pre-created library or fixed result cannot pass.
    EXPECTED_FILE="/tmp/verifier_expected_$$"
    python3 - "$EXPECTED_FILE" <<'PY'
import secrets
import sys
from pathlib import Path

a = secrets.randbelow(80) + 11
b = secrets.randbelow(80) + 17
c = secrets.randbelow(80) + 23
Path("/home/user/workspace/src/modA.c").write_text(f"int getA() {{\n    return {a};\n}}\n")
Path("/home/user/workspace/src/modB.c").write_text(
    f"extern int getA();\nint getB() {{\n    return getA() + {b};\n}}\n"
)
Path("/home/user/workspace/src/modC.c").write_text(
    f"extern int getA();\nint getC() {{\n    return getA() + {c};\n}}\n"
)
Path(sys.argv[1]).write_text(str(2 * a + b + c))
PY
    EXPECTED="$(cat "$EXPECTED_FILE")"

    rm -f /home/user/workspace/modA.so /home/user/workspace/modB.so \
          /home/user/workspace/modC.so /home/user/workspace/modD.so \
          /home/user/workspace/result.txt

    timeout 30s runuser -u user -- env HOME=/home/user \
        python3 /home/user/workspace/builder.py

    test -s "$WS_MARK"
    for lib in modA.so modB.so modC.so modD.so; do
        test -f "/home/user/workspace/$lib"
        readelf -h "/home/user/workspace/$lib" | grep -q 'Type:.*DYN'
    done

    # Instrument ctypes while running the submitted runner. This records the actual
    # library load order, modes, and invocation of getD().
    TRACE_DIR="/tmp/ctypes_instrument_$$"
    TRACE_FILE="/tmp/ctypes_trace_$$"
    mkdir -p "$TRACE_DIR"
    : > "$TRACE_FILE"
    chmod 666 "$TRACE_FILE"
    cat > "$TRACE_DIR/sitecustomize.py" <<'PY'
import ctypes
import os

_trace = os.environ.get("CTYPES_TRACE")
_real_cdll = ctypes.CDLL
_targets = {"modA.so", "modB.so", "modC.so", "modD.so"}

def _write(line):
    if _trace:
        with open(_trace, "a") as f:
            f.write(line + "\n")

class _FunctionProxy:
    def __init__(self, fn, library, name):
        object.__setattr__(self, "_fn", fn)
        object.__setattr__(self, "_library", library)
        object.__setattr__(self, "_name", name)
    def __call__(self, *args, **kwargs):
        _write(f"CALL|{self._library}|{self._name}")
        return self._fn(*args, **kwargs)
    def __getattr__(self, name):
        return getattr(self._fn, name)
    def __setattr__(self, name, value):
        setattr(self._fn, name, value)

class _LibraryProxy:
    def __init__(self, library, name):
        object.__setattr__(self, "_library", library)
        object.__setattr__(self, "_name", name)
    def __getattr__(self, name):
        value = getattr(self._library, name)
        if name == "getD" and self._name == "modD.so":
            return _FunctionProxy(value, self._name, name)
        return value
    def __setattr__(self, name, value):
        setattr(self._library, name, value)

def _traced_cdll(name, *args, **kwargs):
    mode = kwargs.get("mode", args[0] if args else ctypes.DEFAULT_MODE)
    library = _real_cdll(name, *args, **kwargs)
    base = os.path.basename(os.fspath(name)) if name is not None else ""
    if base in _targets:
        _write(f"LOAD|{base}|{int(mode)}")
        return _LibraryProxy(library, base)
    return library

ctypes.CDLL = _traced_cdll
ctypes.cdll._dlltype = _traced_cdll
PY

    timeout 30s runuser -u user -- env HOME=/home/user \
        PYTHONPATH="$TRACE_DIR" CTYPES_TRACE="$TRACE_FILE" \
        python3 /home/user/workspace/run_test.py

    python3 - "$TRACE_FILE" "$EXPECTED" <<'PY'
import ctypes
import os
import sys

trace_path, expected_text = sys.argv[1], sys.argv[2]
expected = int(expected_text)
with open(trace_path) as f:
    lines = [line.strip() for line in f if line.strip()]

loads = []
for line in lines:
    parts = line.split("|")
    if parts[0] == "LOAD":
        assert len(parts) == 3, f"Malformed ctypes load trace: {line}"
        name, mode = parts[1], int(parts[2])
        assert mode & ctypes.RTLD_GLOBAL, f"{name} was not loaded with ctypes.RTLD_GLOBAL"
        loads.append(name)

valid_orders = [
    ["modA.so", "modB.so", "modC.so", "modD.so"],
    ["modA.so", "modC.so", "modB.so", "modD.so"],
]
assert loads in valid_orders, f"Libraries were not loaded exactly once in topological order: {loads}"
assert "CALL|modD.so|getD" in lines, "run_test.py did not call getD() from modD.so"

result_path = "/home/user/workspace/result.txt"
assert os.path.isfile(result_path), "run_test.py did not create result.txt"
with open(result_path) as f:
    actual_text = f.read().strip()
assert actual_text == str(expected), f"Expected dynamic result {expected}, found {actual_text!r}"

# Independently exercise the newly built ELF libraries and derive getD's value.
workspace = "/home/user/workspace"
handles = []
for name in loads:
    handles.append(ctypes.CDLL(os.path.join(workspace, name), mode=ctypes.RTLD_GLOBAL))
fn = handles[-1].getD
fn.restype = ctypes.c_int
assert fn() == expected, "Compiled modD.so did not produce the value derived from the source inputs"
PY

    # Restore the provided inputs and execute both artifacts again, preserving the
    # original verifier's exact final-state assertion that result.txt is 70.
    cp -f "$BACKUP_DIR/src/"*.c /home/user/workspace/src/
    rm -f /home/user/workspace/modA.so /home/user/workspace/modB.so \
          /home/user/workspace/modC.so /home/user/workspace/modD.so \
          /home/user/workspace/result.txt
    timeout 30s runuser -u user -- env HOME=/home/user \
        python3 /home/user/workspace/builder.py
    : > "$TRACE_FILE"
    timeout 30s runuser -u user -- env HOME=/home/user \
        PYTHONPATH="$TRACE_DIR" CTYPES_TRACE="$TRACE_FILE" \
        python3 /home/user/workspace/run_test.py

    python3 - <<'PY'
import os
workspace = "/home/user/workspace"
assert os.path.isfile(os.path.join(workspace, "builder.py"))
assert os.path.isfile(os.path.join(workspace, "run_test.py"))
for name in ("modA.so", "modB.so", "modC.so", "modD.so"):
    assert os.path.isfile(os.path.join(workspace, name)), f"Compiled library {name} is missing"
with open(os.path.join(workspace, "result.txt")) as f:
    content = f.read().strip()
assert content == "70", f"Expected result.txt to contain '70', but found '{content}'."
PY
)

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
