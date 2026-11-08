#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import http.server
import json
import os
import secrets
import socket
import subprocess
import threading
import time


def get_response(port, path, timeout=3):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    try:
        conn.request("GET", path)
        response = conn.getresponse()
        return response.status, response.read()
    finally:
        conn.close()


def test_config_updated():
    config_path = "/home/user/microservices/config.json"
    assert os.path.isfile(config_path), f"File {config_path} does not exist."

    with open(config_path, "r") as f:
        config = json.load(f)

    assert config.get("email_port") == 8025, f"Expected email_port to be 8025, but got {config.get('email_port')}."
    assert config.get("api_ports") == [8081, 8082], "api_ports should remain [8081, 8082]."
    assert config.get("proxy_port") == 8080, "proxy_port should remain 8080."


def test_router_script_exists():
    router_path = "/home/user/router.py"
    assert os.path.isfile(router_path), f"Router script {router_path} does not exist."


def test_verify_script_exists():
    verify_path = "/home/user/verify.sh"
    assert os.path.isfile(verify_path), f"Verification script {verify_path} does not exist."


def test_routing_log_contents():
    log_path = "/home/user/routing.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read()

    expected_1 = "API_RESPONSE_8081API_RESPONSE_8082EMAIL_SERVICE_ACK"
    expected_2 = "API_RESPONSE_8082API_RESPONSE_8081EMAIL_SERVICE_ACK"

    assert content in (expected_1, expected_2), (
        "routing.log content does not match the expected round-robin output.\n"
        f"Got: '{content}'\n"
        f"Expected either '{expected_1}' or '{expected_2}'."
    )


def test_services_were_started_and_router_is_live():
    expected = {
        8081: b"API_RESPONSE_8081",
        8082: b"API_RESPONSE_8082",
        8025: b"EMAIL_SERVICE_ACK",
    }
    for port, body in expected.items():
        status, actual = get_response(port, "/health")
        assert status == 200, f"Service on port {port} did not return HTTP 200."
        assert actual == body, f"Unexpected response from service on port {port}: {actual!r}"

    status, body = get_response(8080, "/email")
    assert status == 200, "The running router did not return HTTP 200 for /email."
    assert body == b"EMAIL_SERVICE_ACK", "The running router did not proxy /email correctly."


def make_handler(body):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            pass

    return Handler


class ReusableThreadingHTTPServer(http.server.ThreadingHTTPServer):
    allow_reuse_address = True


def wait_for_port(port, timeout=6):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError(f"Timed out waiting for port {port} to accept connections.")


def test_router_behavior_and_verify_automation_with_runtime_responses():
    log_path = "/home/user/routing.log"
    with open(log_path, "rb") as f:
        original_log = f.read()

    # Stop the submitted background instances so the submitted router can be
    # exercised from a clean initial round-robin state against unpredictable
    # backend response bodies.
    subprocess.run(["pkill", "-f", "/home/user/router.py"], check=False)
    subprocess.run(["pkill", "-f", "/home/user/microservices/start_services.py"], check=False)
    time.sleep(0.5)

    token1 = ("API1_" + secrets.token_hex(16)).encode()
    token2 = ("API2_" + secrets.token_hex(16)).encode()
    email_token = ("MAIL_" + secrets.token_hex(16)).encode()
    marker = ("PREFIX_" + secrets.token_hex(12)).encode()

    servers = []
    threads = []
    router = None
    try:
        for port, body in ((8081, token1), (8082, token2), (8025, email_token)):
            server = ReusableThreadingHTTPServer(("127.0.0.1", port), make_handler(body))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            servers.append(server)
            threads.append(thread)

        router = subprocess.Popen(
            ["python3", "/home/user/router.py"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        wait_for_port(8080)
        assert router.poll() is None, "router.py exited instead of serving requests."

        # An email request must not consume an API round-robin turn.
        requests = [
            ("/api", token1),
            ("/api", token2),
            ("/email", email_token),
            ("/api", token1),
            ("/api", token2),
        ]
        for path, expected_body in requests:
            status, body = get_response(8080, path)
            assert status == 200, f"Router returned HTTP {status} for {path}."
            assert body == expected_body, (
                f"Router returned {body!r} for {path}; expected exact backend body {expected_body!r}."
            )

        # Four API requests above leave the next turn at 8081. Seeding the log
        # also verifies that verify.sh appends rather than replacing its content.
        with open(log_path, "wb") as f:
            f.write(marker)

        result = subprocess.run(
            ["bash", "/home/user/verify.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"verify.sh failed with exit code {result.returncode}: {result.stderr.decode(errors='replace')}"
        )

        with open(log_path, "rb") as f:
            generated = f.read()
        assert generated == marker + token1 + token2 + email_token, (
            "verify.sh did not append the three required requests in the required order. "
            f"Got {generated!r}."
        )
    finally:
        if router is not None and router.poll() is None:
            router.terminate()
            try:
                router.wait(timeout=3)
            except subprocess.TimeoutExpired:
                router.kill()
                router.wait(timeout=3)
        subprocess.run(["pkill", "-f", "/home/user/router.py"], check=False)
        for server in servers:
            server.shutdown()
            server.server_close()
        for thread in threads:
            thread.join(timeout=2)
        with open(log_path, "wb") as f:
            f.write(original_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
