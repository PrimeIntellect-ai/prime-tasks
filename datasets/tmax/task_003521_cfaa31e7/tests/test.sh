#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import stat
import string
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

CLIENT_SCRIPT = "/home/user/client.sh"
COMPOSE_FILE = "/home/user/app/docker-compose.yml"
APP_DIR = "/home/user/app"
ORACLE_SCRIPT = "/tmp/oracle.sh"


@pytest.fixture(scope="session", autouse=True)
def setup_oracle():
    oracle_content = '#!/bin/bash\necho "${1^^}_ACK"\n'
    with open(ORACLE_SCRIPT, "w") as f:
        f.write(oracle_content)
    st = os.stat(ORACLE_SCRIPT)
    os.chmod(ORACLE_SCRIPT, st.st_mode | stat.S_IEXEC)


def compose(*args, timeout=30, check=True):
    return subprocess.run(
        ["docker-compose", "-f", COMPOSE_FILE, *args],
        cwd=APP_DIR,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=check,
    )


def service_container_ids(service):
    proc = compose("ps", "-q", service)
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


def inspect_container(container_id):
    proc = subprocess.run(
        ["docker", "inspect", container_id],
        capture_output=True,
        text=True,
        timeout=15,
        check=True,
    )
    return json.loads(proc.stdout)[0]


def post_gateway(payload, timeout=5):
    body = ('{"data": "' + payload + '"}').encode()
    request = urllib.request.Request(
        "http://127.0.0.1:8080/process",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.status, json.loads(response.read().decode())


def wait_for_gateway(payload, attempts=30):
    last_error = None
    for _ in range(attempts):
        try:
            status, response = post_gateway(payload, timeout=2)
            if status == 200 and response.get("result") == payload.upper() + "_ACK":
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.5)
    pytest.fail(f"Gateway did not become healthy after restart: {last_error}")


def test_client_script_exists_and_executable():
    assert os.path.exists(CLIENT_SCRIPT), f"Agent script {CLIENT_SCRIPT} does not exist."
    assert os.path.isfile(CLIENT_SCRIPT), f"{CLIENT_SCRIPT} is not a file."
    assert os.access(CLIENT_SCRIPT, os.X_OK), f"{CLIENT_SCRIPT} is not executable."


def test_compose_services_are_running_and_share_a_network():
    gateway_ids = service_container_ids("gateway")
    processor_ids = service_container_ids("processor")
    assert gateway_ids, "The Compose gateway service is not running."
    assert processor_ids, "The Compose processor service is not running."

    gateway_info = [inspect_container(cid) for cid in gateway_ids]
    processor_info = [inspect_container(cid) for cid in processor_ids]
    assert any(info["State"]["Running"] for info in gateway_info), "Gateway container is not running."
    assert any(info["State"]["Running"] for info in processor_info), "Processor container is not running."

    gateway_networks = set().union(*(
        set(info["NetworkSettings"]["Networks"].keys()) for info in gateway_info
    ))
    processor_networks = set().union(*(
        set(info["NetworkSettings"]["Networks"].keys()) for info in processor_info
    ))
    assert gateway_networks & processor_networks, (
        "The running gateway and processor containers do not share a Docker network."
    )

    payload = "network" + secrets.token_hex(6)
    status, response = post_gateway(payload)
    assert status == 200
    assert response.get("status") == "ok"
    assert response.get("result") == payload.upper() + "_ACK"


def test_fuzz_equivalence():
    random.seed(42)

    for i in range(50):
        length = random.randint(5, 32)
        fuzz_input = ''.join(random.choices(string.ascii_letters + string.digits, k=length))

        oracle_proc = subprocess.run(
            [ORACLE_SCRIPT, fuzz_input],
            capture_output=True,
            text=True,
            check=True
        )
        expected_output = oracle_proc.stdout.strip()

        try:
            agent_proc = subprocess.run(
                ["/bin/bash", CLIENT_SCRIPT, fuzz_input],
                capture_output=True,
                text=True,
                timeout=5
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input '{fuzz_input}'. "
                        "This likely means the Docker Compose network is still misconfigured "
                        "and the request is hanging.")

        agent_output = agent_proc.stdout.strip()

        assert agent_proc.returncode == 0, (
            f"Agent script failed with return code {agent_proc.returncode} on input '{fuzz_input}'.\n"
            f"Stderr: {agent_proc.stderr}"
        )

        assert agent_output == expected_output, (
            f"Output mismatch on input '{fuzz_input}'.\n"
            f"Expected (Oracle): {expected_output}\n"
            f"Actual (Agent): {agent_output}"
        )


def test_client_makes_exact_http_request_and_parses_response():
    argument = "probe" + secrets.token_hex(8)
    secret_result = "SERVER_RESPONSE_" + secrets.token_hex(16)
    received = []

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            received.append({
                "method": self.command,
                "path": self.path,
                "content_type": self.headers.get("Content-Type"),
                "body": body,
            })
            response = json.dumps({"status": "ok", "result": secret_result}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(response)))
            self.end_headers()
            self.wfile.write(response)

        def log_message(self, format, *args):
            pass

    server = None
    thread = None
    compose("stop", "gateway", timeout=30)
    try:
        server = HTTPServer(("127.0.0.1", 8080), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        try:
            proc = subprocess.run(
                ["/bin/bash", CLIENT_SCRIPT, argument],
                capture_output=True,
                text=True,
                timeout=8,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("Client timed out while an HTTP server was available on the required address.")

        assert proc.returncode == 0, f"Client failed: {proc.stderr}"
        assert proc.stdout.strip() == secret_result, (
            "Client did not print the result supplied by the HTTP response."
        )
        assert len(received) == 1, f"Expected exactly one HTTP request, received {len(received)}."
        request = received[0]
        assert request["method"] == "POST"
        assert request["path"] == "/process"
        assert request["content_type"] == "application/json"
        assert request["body"] == ('{"data": "' + argument + '"}').encode(), (
            f"Incorrect JSON request body: {request['body']!r}"
        )
    finally:
        if server is not None:
            server.shutdown()
            server.server_close()
        if thread is not None:
            thread.join(timeout=3)
        compose("start", "gateway", timeout=30, check=False)

    wait_for_gateway("restored" + secrets.token_hex(4))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
