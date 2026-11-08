#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


def wait_for_port(port, timeout=5.0):
    start = time.time()
    while time.time() - start < timeout:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                return True
        except OSError:
            time.sleep(0.05)
    return False


class AuditServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, address, handler, target_id, flag):
        super().__init__(address, handler)
        self.target_id = target_id
        self.flag = flag
        self.lock = threading.Lock()
        self.seen_ids = set()
        self.active = 0
        self.max_active = 0
        self.valid_header_requests = 0


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        pass

    def reply(self, status, body):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        if (self.headers.get("X-Admin-Bypass") != "true" or
                self.headers.get("X-CSP-Enforce") != "none"):
            self.reply(403, "Forbidden\n")
            return

        parsed = urlparse(self.path)
        if parsed.path != "/verify":
            self.reply(404, "Not Found\n")
            return

        try:
            values = parse_qs(parsed.query, keep_blank_values=True).get("id", [])
            request_id = int(values[0])
        except (ValueError, IndexError):
            self.reply(404, "Not Found\n")
            return

        if request_id < 0 or request_id > 20000:
            self.reply(404, "Not Found\n")
            return

        with self.server.lock:
            self.server.valid_header_requests += 1
            self.server.seen_ids.add(request_id)
            self.server.active += 1
            self.server.max_active = max(self.server.max_active, self.server.active)

        try:
            time.sleep(0.002)
            if request_id == self.server.target_id:
                self.reply(200, self.server.flag)
            else:
                self.reply(404, "Not Found\n")
        finally:
            with self.server.lock:
                self.server.active -= 1


def test_audit_go_performance_and_correctness():
    audit_file = "/home/user/audit.go"
    assert os.path.isfile(audit_file), f"File {audit_file} does not exist."

    subprocess.run(["pkill", "-f", "auth_daemon"], check=False)
    time.sleep(0.1)

    # Use an unpredictable vulnerable ID and flag so a constant-printing program
    # cannot pass. Keeping the ID high also exercises an actual scan from zero.
    target_id = 18000 + secrets.randbelow(2001)
    expected_flag = f"FLAG{{runtime_{secrets.token_hex(16)}}}"
    server = AuditServer(("127.0.0.1", 8080), Handler, target_id, expected_flag)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    try:
        assert wait_for_port(8080), "Daemon did not start listening on port 8080."

        start_time = time.time()
        proc = subprocess.run(
            ["go", "run", audit_file],
            capture_output=True,
            text=True,
            timeout=5.0,
        )
        duration = time.time() - start_time
        output = proc.stdout.strip()

        assert proc.returncode == 0, (
            f"Go program failed with return code {proc.returncode}. Stderr:\n{proc.stderr}"
        )
        assert output == expected_flag, (
            f"Go program output was incorrect. Expected '{expected_flag}', got '{output}'"
        )
        assert duration <= 1.0, (
            f"Execution time metric failed: took {duration:.3f}s, threshold is <= 1.0s."
        )

        with server.lock:
            seen_ids = set(server.seen_ids)
            max_active = server.max_active
            valid_header_requests = server.valid_header_requests

        assert target_id in seen_ids, "The program did not request the vulnerable ID."
        assert valid_header_requests > 0, "No requests supplied the required bypass headers."
        assert 0 in seen_ids, "The program did not dynamically scan the ID range from zero."
        assert len(seen_ids) >= 10000, (
            f"Too few distinct IDs were scanned: observed {len(seen_ids)}."
        )
        assert max_active >= 8, (
            f"The scan was not heavily concurrent: only {max_active} simultaneous requests observed."
        )
    finally:
        server.shutdown()
        server.server_close()
        server_thread.join(timeout=1.0)


if __name__ == "__main__":
    test_audit_go_performance_and_correctness()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
