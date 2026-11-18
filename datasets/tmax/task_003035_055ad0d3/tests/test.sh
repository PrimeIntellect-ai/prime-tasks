#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import http.server
import json
import os
import secrets
import signal
import socketserver
import subprocess
import tempfile
import threading
import time

SCRIPT_PATH = "/home/user/analyze_traffic.sh"
PORT = 8080


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable. Did you run chmod +x?"


def stop_existing_listener():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        state = fields[3]
                        if local_port == PORT and state == "0A":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(pid))
                    break
        except (FileNotFoundError, PermissionError):
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.5)


def encrypt_payload(payload, key_hex):
    result = subprocess.run(
        ["openssl", "enc", "-aes-128-ecb", "-K", key_hex, "-nosalt", "-base64", "-A"],
        input=payload.encode(),
        capture_output=True,
        check=True,
    )
    return result.stdout.decode().strip()


def make_ocr_verified_image(directory, index, payload):
    for attempt in range(30):
        key_hex = secrets.token_hex(16)
        ciphertext = encrypt_payload(payload, key_hex)
        image_path = os.path.join(directory, f"hidden_dashboard_{index}_{attempt}.png")
        text = f"Target: localhost:8080\nKEY: {key_hex}\nPAYLOAD: {ciphertext}"
        subprocess.run(
            [
                "convert", "-size", "1200x360", "xc:white",
                "-font", "DejaVu-Sans-Mono", "-pointsize", "28",
                "-fill", "black", "-interline-spacing", "12",
                "-annotate", "+45+65", text, image_path,
            ],
            check=True,
            capture_output=True,
        )
        ocr = subprocess.run(
            ["tesseract", image_path, "stdout"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        if f"KEY: {key_hex}" in ocr and f"PAYLOAD: {ciphertext}" in ocr:
            return image_path
    raise AssertionError("Could not generate a reliably OCR-readable hidden test image")


class ReusableHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def test_accuracy_metric():
    assert os.path.isfile("/app/dashboard.png"), "Test image /app/dashboard.png is missing."

    hidden_dir = tempfile.mkdtemp(prefix="traffic_hidden_")
    hidden_payloads = [
        f"probe_{secrets.token_hex(10)}",
        f"audit_{secrets.token_hex(11)}",
        f"check_{secrets.token_hex(12)}",
    ]
    hidden_cases = []
    responses = {"' OR 1=1 --": "FLAG{sqli_success_123}"}

    for index, payload in enumerate(hidden_payloads):
        image_path = make_ocr_verified_image(hidden_dir, index, payload)
        response = f"RESULT{{{secrets.token_hex(20)}}}"
        responses[payload] = response
        hidden_cases.append((image_path, payload, response))

    test_cases = [
        ("/app/dashboard.png", "' OR 1=1 --", "FLAG{sqli_success_123}"),
        *hidden_cases,
    ]
    valid_hits = {payload: 0 for _, payload, _ in test_cases}
    lock = threading.Lock()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != "/vulnerable_endpoint":
                self.send_error(404)
                return
            if self.headers.get_content_type() != "application/json":
                self.send_error(415)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                data = json.loads(self.rfile.read(length).decode("utf-8"))
                query = data["query"]
                if not isinstance(query, str) or query not in responses:
                    raise ValueError("unexpected query")
            except Exception:
                self.send_error(400)
                return

            with lock:
                valid_hits[query] += 1
            body = responses[query].encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    stop_existing_listener()
    server = ReusableHTTPServer(("127.0.0.1", PORT), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    correct = 0
    try:
        for image_path, payload, expected_output in test_cases:
            assert os.path.isfile(image_path), f"Test image {image_path} is missing."
            with lock:
                hits_before = valid_hits[payload]
            try:
                result = subprocess.run(
                    [SCRIPT_PATH, image_path],
                    capture_output=True,
                    text=True,
                    timeout=20,
                )
                with lock:
                    made_valid_request = valid_hits[payload] > hits_before
                if result.stdout.strip() == expected_output and made_valid_request:
                    correct += 1
                else:
                    print(f"Script failed for {image_path}")
                    print(f"Return code: {result.returncode}")
                    print(f"Script stdout:\n{result.stdout}")
                    print(f"Script stderr:\n{result.stderr}")
                    print(f"Valid HTTP request observed: {made_valid_request}")
            except subprocess.TimeoutExpired:
                print(f"Script timed out processing {image_path}")
            except Exception as exc:
                print(f"Error running script: {exc}")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    accuracy = correct / len(test_cases)
    assert accuracy >= 1.0, f"Accuracy metric failed: {accuracy} < 1.0. The script did not correctly process every image and issue the required HTTP requests."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
