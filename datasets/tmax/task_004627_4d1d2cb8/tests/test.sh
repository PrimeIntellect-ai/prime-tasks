#!/bin/bash
set -u
mkdir -p /logs/verifier
overall=1
server_pid=""

stop_server() {
    if [ -n "${server_pid}" ]; then
        kill "${server_pid}" 2>/dev/null || true
        wait "${server_pid}" 2>/dev/null || true
        server_pid=""
    fi
    pkill -f '/home/user/ws_server.py' 2>/dev/null || true
    pkill -f '/tmp/audit_dynamic_ws.py' 2>/dev/null || true
    sleep 1
}

wait_for_port() {
    python3 - <<'PY'
import socket, time, sys
for _ in range(50):
    try:
        with socket.create_connection(("127.0.0.1", 9090), timeout=0.2):
            sys.exit(0)
    except OSError:
        time.sleep(0.1)
sys.exit(1)
PY
}

run_submission() {
    rm -f /home/user/.github/workflows/secure_build.yml
    timeout 25s runuser -u user -- env HOME=/home/user /home/user/audit_resolver.sh
}

trap stop_server EXIT

cat <<'TEST_EOF' > /tmp/test_original_state.py
import os
import re
import pytest

def test_script_exists_and_executable():
    script_path = "/home/user/audit_resolver.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."
    with open(script_path, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").strip()
    assert re.match(r"^#!.*(?:/|\s)bash(?:\s|$)", first_line), "The submission must be a Bash script."

def test_yaml_exists():
    yaml_path = "/home/user/.github/workflows/secure_build.yml"
    assert os.path.isfile(yaml_path), f"The generated workflow file {yaml_path} does not exist."

def test_yaml_content():
    yaml_path = "/home/user/.github/workflows/secure_build.yml"
    if not os.path.isfile(yaml_path):
        pytest.fail(f"Workflow file {yaml_path} missing, cannot check content.")

    with open(yaml_path, 'r') as f:
        content = f.read()

    assert re.search(r"CORE_VERSION:\s*1\.1\.0", content), "CORE_VERSION is not correctly resolved to 1.1.0"
    assert re.search(r"WEB_VERSION:\s*2\.1\.0", content), "WEB_VERSION is not correctly resolved to 2.1.0"
    assert re.search(r"AUTH_VERSION:\s*3\.0\.0", content), "AUTH_VERSION is not correctly resolved to 3.0.0"

    assert "name: Secure Build" in content, "Missing 'name: Secure Build' in YAML."
    assert "on: [push]" in content, "Missing 'on: [push]' in YAML."
    assert "runs-on: ubuntu-latest" in content, "Missing 'runs-on: ubuntu-latest' in YAML."
    assert "uses: actions/checkout@v3" in content, "Missing checkout step in YAML."
    assert "run: ./install.sh $CORE_VERSION $WEB_VERSION $AUTH_VERSION" in content, "Missing or incorrect install step in YAML."
TEST_EOF

# First retain and exercise all original checks against the supplied catalog.
stop_server
python3 /home/user/ws_server.py >/tmp/original_ws.log 2>&1 &
server_pid=$!
if ! wait_for_port || ! run_submission || ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_original_state.py -x --tb=short; then
    overall=0
fi
stop_server

cat <<'PY_EOF' > /tmp/audit_dynamic_ws.py
import asyncio
import base64
import hashlib
import json
import secrets
import sys
import websockets

mode = int(sys.argv[1])
expected_path = sys.argv[2]
marker_path = sys.argv[3]
rng = secrets.SystemRandom()
used = set()

def version():
    while True:
        v = f"{rng.randrange(4, 90)}.{rng.randrange(0, 90)}.{rng.randrange(0, 90)}"
        if v not in used:
            used.add(v)
            return v

bad_core = version()
decoy_core = version()
good_core = version()
bad_web = version()
decoy_web = version()
good_web = version()
bad_auth = version()
good_auth = version()

def pkg(name, ver, dep, tampered=False):
    content = secrets.token_bytes(31)
    encoded = base64.b64encode(content).decode()
    digest = hashlib.sha256(content).hexdigest()
    if tampered:
        digest = ("0" if digest[0] != "0" else "1") + digest[1:]
    return f"PKG {name} {ver} {digest} {encoded} {dep}"

bad_chain = [
    pkg("core-lib", bad_core, "NONE", tampered=True),
    pkg("web-framework", bad_web, f"core-lib={bad_core}"),
    pkg("auth-plugin", bad_auth, f"web-framework={bad_web}"),
]
good_chain = [
    pkg("core-lib", good_core, "NONE"),
    pkg("web-framework", good_web, f"core-lib={good_core}"),
    pkg("auth-plugin", good_auth, f"web-framework={good_web}"),
]
decoys = [
    pkg("core-lib", decoy_core, "NONE"),
    pkg("web-framework", decoy_web, f"core-lib={decoy_core}"),
]

# Use opposite candidate order in the two runs so selecting the first or last
# dependency-compatible tree without checking hashes cannot consistently pass.
chains = [bad_chain, good_chain] if mode == 0 else [good_chain, bad_chain]
packages = []
for i in range(3):
    packages.append(chains[0][i])
    if i < 2:
        packages.append(decoys[i])
    packages.append(chains[1][i])

with open(expected_path, "w") as f:
    json.dump({"core": good_core, "web": good_web, "auth": good_auth}, f)

async def handler(websocket):
    with open(marker_path, "w") as f:
        f.write("connected\n")
    for line in packages:
        await websocket.send(line)
    await websocket.close()

async def main():
    async with websockets.serve(handler, "localhost", 9090):
        await asyncio.Future()

asyncio.run(main())
PY_EOF

cat <<'PY_EOF' > /tmp/check_dynamic_result.py
import json
import os
import sys

expected_path, marker_path = sys.argv[1], sys.argv[2]
workflow = "/home/user/.github/workflows/secure_build.yml"
assert os.path.isfile(marker_path), "The submitted script did not connect to the WebSocket server"
assert os.path.isfile(workflow), "The submitted script did not generate the workflow"
with open(expected_path) as f:
    e = json.load(f)
with open(workflow) as f:
    actual = f.read()
expected = f"""name: Secure Build
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    env:
      CORE_VERSION: {e['core']}
      WEB_VERSION: {e['web']}
      AUTH_VERSION: {e['auth']}
    steps:
      - name: Checkout
        uses: actions/checkout@v3
      - name: Install
        run: ./install.sh $CORE_VERSION $WEB_VERSION $AUTH_VERSION
"""
assert actual == expected, f"Generated workflow did not exactly match the dynamically resolved safe dependency tree.\nExpected:\n{expected}\nActual:\n{actual}"
PY_EOF

# Exercise fresh, unpredictable catalogs. Each contains a fully compatible tree
# whose core package has a forged hash, plus one uniquely valid safe tree.
for mode in 0 1; do
    expected="/tmp/audit_expected_${mode}.json"
    marker="/tmp/audit_connected_${mode}"
    rm -f "$expected" "$marker"
    python3 /tmp/audit_dynamic_ws.py "$mode" "$expected" "$marker" >/tmp/dynamic_ws_${mode}.log 2>&1 &
    server_pid=$!
    if ! wait_for_port || ! run_submission || ! python3 /tmp/check_dynamic_result.py "$expected" "$marker"; then
        overall=0
    fi
    stop_server
done

if [ "$overall" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
