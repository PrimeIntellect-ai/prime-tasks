#!/bin/bash
set -u
mkdir -p /logs/verifier

passed=1
oracle="/app/telemetry_oracle"
backup_dir="$(mktemp -d /tmp/verifier-oracle.XXXXXX)"
backup="$backup_dir/telemetry_oracle"
call_log="$(mktemp /tmp/verifier-oracle-calls.XXXXXX)"
chmod 666 "$call_log"

restore_oracle() {
    rm -f "$oracle"
    if [ -f "$backup" ]; then
        mv "$backup" "$oracle"
    fi
    rm -rf "$backup_dir"
    rm -f "$call_log"
}
trap restore_oracle EXIT

if [ ! -x "$oracle" ]; then
    passed=0
else
    mv "$oracle" "$backup"

    cat > "$oracle" <<EOF
#!/usr/bin/env python3
import base64
import sys
import zlib

if len(sys.argv) != 2:
    raise SystemExit(1)
try:
    data = base64.b64decode(sys.argv[1], validate=True)
except Exception:
    raise SystemExit(1)
with open(${call_log@Q}, "a", encoding="utf-8") as f:
    f.write(sys.argv[1] + "\\n")
value = (zlib.crc32(data) & 0xffffffff) ^ 0xDEADBEEF
print(f"{value:08x}")
EOF
    chmod 755 "$oracle"

    # Confirm that the submitted file contains an actual Hypothesis-decorated
    # test, rather than merely mentioning Hypothesis in a comment or string.
    if ! python3 - <<'PY'
import importlib.util
import inspect
import os

path = "/home/user/test_checksum.py"
assert os.path.isfile(path), f"Property-based test file {path} does not exist"
spec = importlib.util.spec_from_file_location("submitted_checksum_test", path)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

candidates = []
for name, value in vars(module).items():
    if name.startswith("test") and callable(value):
        candidates.append(value)
    if inspect.isclass(value):
        for member_name, member in vars(value).items():
            if member_name.startswith("test") and callable(member):
                candidates.append(member)

assert any(
    getattr(fn, "is_hypothesis_test", False) or hasattr(fn, "hypothesis")
    for fn in candidates
), "No actual Hypothesis-decorated test was found"
PY
    then
        passed=0
    fi

    # Ignore any import-time activity. The oracle calls counted below must be
    # made while pytest actually executes the submitted property test.
    : > "$call_log"
    if ! timeout 90s python3 -m pytest /home/user/test_checksum.py -x --tb=short; then
        passed=0
    fi

    if ! python3 - "$call_log" <<'PY'
import base64
import sys

values = set()
with open(sys.argv[1], encoding="utf-8") as f:
    for line in f:
        encoded = line.rstrip("\n")
        try:
            values.add(base64.b64decode(encoded, validate=True))
        except Exception:
            pass
assert len(values) >= 10, (
    "The executed property test did not compare against the oracle on "
    "enough distinct byte sequences"
)
PY
    then
        passed=0
    fi

    # Keep the real oracle unavailable while exercising the running server, so
    # a server that shells out to /app/telemetry_oracle cannot pass.
    rm -f "$oracle"
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import zlib
import base64
import asyncio
import pytest

try:
    import websockets
except ImportError:
    websockets = None

def get_expected_checksum(data: bytes) -> str:
    crc = zlib.crc32(data) & 0xFFFFFFFF
    final = crc ^ 0xDEADBEEF
    return f"{final:08x}"

def test_hypothesis_file_exists():
    path = "/home/user/test_checksum.py"
    assert os.path.isfile(path), f"Property-based test file {path} does not exist"
    with open(path, "r") as f:
        content = f.read()
    assert "hypothesis" in content, f"{path} does not seem to import or use 'hypothesis'"

def test_websocket_server_behavior():
    if websockets is None:
        pytest.fail("The 'websockets' library is not installed in the test environment.")

    async def run_ws_test():
        uri = "ws://127.0.0.1:8765/telemetry"
        test_cases = [
            (1, b"Hello World"),
            (42, b"Telemetry Data 123!@#"),
            (99, b""),
            (100, os.urandom(64)),
        ]

        try:
            async with websockets.connect(uri) as websocket:
                for req_id, data in test_cases:
                    b64_data = base64.b64encode(data).decode("utf-8")
                    req = {"id": req_id, "data": b64_data}
                    await websocket.send(json.dumps(req))

                    try:
                        response_str = await asyncio.wait_for(websocket.recv(), timeout=2.0)
                    except asyncio.TimeoutError:
                        pytest.fail(f"Timeout waiting for response to message id {req_id}")

                    try:
                        response = json.loads(response_str)
                    except json.JSONDecodeError:
                        pytest.fail(f"Server returned invalid JSON: {response_str}")

                    assert response.get("id") == req_id, f"Expected id {req_id}, got {response.get('id')}"
                    assert response.get("status") == "ack", f"Expected status 'ack', got {response.get('status')}"

                    expected_checksum = get_expected_checksum(data)
                    actual_checksum = response.get("checksum")
                    assert actual_checksum == expected_checksum, (
                        f"Checksum mismatch for data {data!r}. "
                        f"Expected {expected_checksum}, got {actual_checksum}"
                    )
        except ConnectionRefusedError:
            pytest.fail("Connection refused. The WebSocket server is not running or not listening on 127.0.0.1:8765.")
        except websockets.exceptions.InvalidURI:
            pytest.fail("Invalid WebSocket URI.")
        except Exception as e:
            pytest.fail(f"WebSocket client encountered an error: {e}")

    asyncio.run(run_ws_test())
TEST_EOF

if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short; then
    passed=0
fi

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
