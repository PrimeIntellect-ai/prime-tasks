#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import secrets
import stat
import subprocess
import time


def stop_node_servers():
    subprocess.run(["pkill", "-x", "node"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.2)


def dynamic_names(count=17):
    token = secrets.token_hex(6)
    return [f"artifact_{token}_{i}" for i in range(count)]


def server_source(names):
    messages = []
    for i, name in enumerate(names):
        deps = "" if i == 0 else names[i - 1]
        messages.append(f"[ARTIFACT] name:{name} | deps:{deps};")
    messages.append("EOF")
    return """const WebSocket = require('/home/user/node_modules/ws');
const wss = new WebSocket.Server({ port: 8080 });
wss.on('connection', function connection(ws) {
  const messages = %s;
  messages.forEach(message => ws.send(message));
});
""" % json.dumps(messages)


def processed_names(stdout):
    lines = [line.strip() for line in stdout.splitlines() if line.strip()]
    prefix = "Processed: "
    assert all(line.startswith(prefix) for line in lines), f"Unexpected client output: {stdout!r}"
    return [line[len(prefix):] for line in lines]


def test_e2e_script_exists_and_executable():
    script_path = "/home/user/e2e.sh"
    assert os.path.isfile(script_path), f"Missing script: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"


def test_e2e_script_execution_and_output():
    script_path = "/home/user/e2e.sh"
    output_log = "/home/user/output.log"

    stop_node_servers()
    if os.path.exists(output_log):
        os.remove(output_log)

    try:
        result = subprocess.run(
            [script_path], capture_output=True, text=True, cwd="/home/user", timeout=30
        )
    finally:
        stop_node_servers()

    assert result.returncode == 0, (
        f"e2e.sh exited with non-zero status code: {result.returncode}\n"
        f"Stderr: {result.stderr}"
    )
    assert os.path.isfile(output_log), f"output.log was not created at {output_log}"

    with open(output_log, "r") as f:
        content = f.read()

    expected_artifacts = ["Processed: core", "Processed: utils", "Processed: app"]
    for artifact in expected_artifacts:
        assert artifact in content, (
            f"Expected '{artifact}' in output.log, but it was not found. Content:\n{content}"
        )


def test_go_client_against_verifier_generated_artifacts():
    client_path = "/home/user/client.go"
    assert os.path.isfile(client_path), f"Missing Go client: {client_path}"

    names = dynamic_names()
    temp_server = "/tmp/verifier_dynamic_server.js"
    with open(temp_server, "w") as f:
        f.write(server_source(names))

    stop_node_servers()
    server = subprocess.Popen(
        ["node", temp_server], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    try:
        time.sleep(1)
        assert server.poll() is None, "Verifier WebSocket server failed to start"
        result = subprocess.run(
            ["go", "run", client_path],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Go client failed with status {result.returncode}\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        actual = processed_names(result.stdout)
        assert collections.Counter(actual) == collections.Counter(names), (
            f"Client did not process the generated artifacts exactly once. "
            f"Expected {names!r}, got {actual!r}"
        )
    finally:
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()
        stop_node_servers()


def test_e2e_uses_server_and_client_with_generated_artifacts():
    script_path = "/home/user/e2e.sh"
    server_path = "/home/user/server.js"
    output_log = "/home/user/output.log"
    names = dynamic_names(11)

    with open(server_path, "rb") as f:
        original_server = f.read()
    original_mode = stat.S_IMODE(os.stat(server_path).st_mode)

    stop_node_servers()
    try:
        with open(server_path, "w") as f:
            f.write(server_source(names))
        if os.path.exists(output_log):
            os.remove(output_log)

        result = subprocess.run(
            [script_path], capture_output=True, text=True, cwd="/home/user", timeout=30
        )
        assert result.returncode == 0, (
            f"e2e.sh failed on generated server data with status {result.returncode}\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert os.path.isfile(output_log), "e2e.sh did not create /home/user/output.log"
        with open(output_log, "r") as f:
            content = f.read()
        actual = processed_names(content)
        assert collections.Counter(actual) == collections.Counter(names), (
            f"e2e output did not contain the verifier-generated artifacts exactly once. "
            f"Expected {names!r}, got {actual!r}"
        )
    finally:
        stop_node_servers()
        with open(server_path, "wb") as f:
            f.write(original_server)
        os.chmod(server_path, original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
