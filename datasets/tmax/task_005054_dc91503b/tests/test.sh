#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import re
import secrets
import shutil
import socket
import ssl
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, **kwargs)


def stop_services():
    subprocess.run(["nginx", "-s", "quit", "-c", "/app/nginx/nginx.conf"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "auth"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)


def test_client_certs_exist_and_are_valid():
    assert os.path.isfile("/app/certs/client.crt"), "/app/certs/client.crt is missing. You must generate a client certificate."
    assert os.path.isfile("/app/certs/client.key"), "/app/certs/client.key is missing. You must generate a client private key."

    verified = run([
        "openssl", "verify", "-purpose", "sslclient",
        "-CAfile", "/app/certs/ca.crt", "/app/certs/client.crt"
    ])
    assert verified.returncode == 0, f"Client certificate is not validly signed by the supplied CA: {verified.stderr}"

    cert_pub = run(["openssl", "x509", "-in", "/app/certs/client.crt", "-pubkey", "-noout"])
    key_pub = run(["openssl", "pkey", "-in", "/app/certs/client.key", "-pubout"])
    assert cert_pub.returncode == 0, f"Invalid client certificate: {cert_pub.stderr}"
    assert key_pub.returncode == 0, f"Invalid client private key: {key_pub.stderr}"
    assert cert_pub.stdout == key_pub.stdout, "The client certificate and private key do not match"


def test_nginx_configuration_contains_mtls_upstream():
    checked = run(["nginx", "-t", "-c", "/app/nginx/nginx.conf"])
    assert checked.returncode == 0, f"Invalid Nginx configuration: {checked.stderr}"

    dumped = run(["nginx", "-T", "-c", "/app/nginx/nginx.conf"])
    assert dumped.returncode == 0, f"Could not inspect Nginx configuration: {dumped.stderr}"
    config = re.sub(r"#.*", "", dumped.stdout + dumped.stderr)
    assert re.search(r"\blisten\s+127\.0\.0\.1:8080\s*;", config), "Nginx must listen on 127.0.0.1:8080"
    assert re.search(r"\bproxy_pass\s+https://127\.0\.0\.1:8443(?:/)?\s*;", config), "Nginx must proxy to https://127.0.0.1:8443"
    assert re.search(r"\bproxy_ssl_certificate\s+/app/certs/client\.crt\s*;", config), "Nginx is not configured to present /app/certs/client.crt"
    assert re.search(r"\bproxy_ssl_certificate_key\s+/app/certs/client\.key\s*;", config), "Nginx is not configured to use /app/certs/client.key"


def test_nginx_mtls_health():
    stop_services()
    challenge_path = "/__mtls_verify_" + secrets.token_hex(16)
    challenge_body = "verified-" + secrets.token_hex(24)
    observed = {"client_cert": False, "challenge": False}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            peer = self.connection.getpeercert()
            if peer:
                observed["client_cert"] = True
            path = self.path.split("?", 1)[0]
            if path == challenge_path:
                observed["challenge"] = True
                body = challenge_body
            elif path == "/health":
                body = '{"status": "ok"}'
            else:
                body = "not found"
            self.send_response(200 if path in (challenge_path, "/health") else 404)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 8443), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain("/app/certs/server.crt", "/app/certs/server.key")
    context.load_verify_locations(cafile="/app/certs/ca.crt")
    context.verify_mode = ssl.CERT_REQUIRED
    server.socket = context.wrap_socket(server.socket, server_side=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        subprocess.Popen(["/app/start.sh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        def fetch(path):
            try:
                with urllib.request.urlopen("http://127.0.0.1:8080" + path, timeout=2) as response:
                    return response.getcode(), response.read().decode("utf-8")
            except Exception:
                return None, None

        code = body = None
        for _ in range(20):
            time.sleep(0.25)
            code, body = fetch("/health")
            if code is not None:
                break

        assert code is not None, "Could not reach http://127.0.0.1:8080/health. Services failed to start or Nginx is misconfigured."
        assert code == 200, f"Expected HTTP 200 from health endpoint, got {code}. Check mTLS Nginx configuration."
        assert '{"status": "ok"}' in body, f"Unexpected response body: {body}"

        challenge_code, returned = fetch(challenge_path)
        assert challenge_code == 200, "A randomized request was not proxied to the TLS backend"
        assert returned == challenge_body, "Nginx did not return the randomized backend response"
        assert observed["challenge"], "The verifier's backend did not receive the proxied request"
        assert observed["client_cert"], "The backend did not receive a CA-verified client certificate during the TLS connection"
    finally:
        stop_services()
        server.shutdown()
        server.server_close()


def test_classifier_exists():
    assert os.path.isfile("/app/classifier.go"), "/app/classifier.go is missing."
    assert os.path.isfile("/app/classifier"), "/app/classifier executable is missing. Did you compile your Go program?"
    assert os.access("/app/classifier", os.X_OK), "/app/classifier is not executable."


def classify(payload):
    return subprocess.run(["/app/classifier", payload], stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode


def test_classifier_clean_corpus():
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_dir), f"{clean_dir} missing"
    clean_files = os.listdir(clean_dir)
    assert len(clean_files) > 0, "No files found in clean corpus"

    failed = []
    for name in clean_files:
        path = os.path.join(clean_dir, name)
        with open(path, "r") as fp:
            payload = fp.read().strip()
        if classify(payload) != 0:
            failed.append(name)
    assert not failed, f"{len(failed)} of {len(clean_files)} clean modified/rejected. Offending: {failed}"


def test_classifier_evil_corpus():
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_dir), f"{evil_dir} missing"
    evil_files = os.listdir(evil_dir)
    assert len(evil_files) > 0, "No files found in evil corpus"

    failed = []
    for name in evil_files:
        path = os.path.join(evil_dir, name)
        with open(path, "r") as fp:
            payload = fp.read().strip()
        if classify(payload) != 1:
            failed.append(name)
    assert not failed, f"{len(failed)} of {len(evil_files)} evil bypassed. Offending: {failed}"


def test_classifier_on_fresh_randomized_tokens_and_key():
    generator_source = r'''
package main
import (
    "crypto/aes"
    "crypto/cipher"
    "crypto/rand"
    "encoding/base64"
    "encoding/hex"
    "fmt"
    "io"
    "os"
)
func main() {
    key, err := hex.DecodeString(os.Args[1]); if err != nil { panic(err) }
    block, err := aes.NewCipher(key); if err != nil { panic(err) }
    gcm, err := cipher.NewGCM(block); if err != nil { panic(err) }
    nonce := make([]byte, gcm.NonceSize())
    if _, err := io.ReadFull(rand.Reader, nonce); err != nil { panic(err) }
    sealed := gcm.Seal(nil, nonce, []byte(os.Args[2]), nil)
    fmt.Print(base64.StdEncoding.EncodeToString(append(nonce, sealed...)))
}
'''
    with open("/tmp/token_generator.go", "w") as fp:
        fp.write(generator_source)
    built = run(["go", "build", "-o", "/tmp/token_generator", "/tmp/token_generator.go"])
    assert built.returncode == 0, f"Could not build verifier token generator: {built.stderr}"

    key_path = "/app/keys/aes.key"
    with open(key_path, "rb") as fp:
        original_key = fp.read()
    original_mode = os.stat(key_path).st_mode
    fresh_key = secrets.token_hex(32)

    clean_users = [
        "alice_" + secrets.token_hex(8),
        "ordinary user " + secrets.token_hex(7),
        "un ion dro p or  1=1 quote -- " + secrets.token_hex(6),
    ]
    evil_users = [
        "prefix UnIoN suffix " + secrets.token_hex(6),
        "prefix SeLeCt suffix " + secrets.token_hex(6),
        "prefix DrOp suffix " + secrets.token_hex(6),
        "prefix OR 1=1 suffix " + secrets.token_hex(6),
        "prefix ' -- suffix " + secrets.token_hex(6),
    ]

    try:
        with open(key_path, "w") as fp:
            fp.write(fresh_key)
        os.chmod(key_path, original_mode)

        for expected, users in ((0, clean_users), (1, evil_users)):
            for user in users:
                plaintext = json.dumps({"marker": secrets.token_hex(5), "user": user}, separators=(",", ":"))
                generated = run(["/tmp/token_generator", fresh_key, plaintext])
                assert generated.returncode == 0, generated.stderr
                payload = generated.stdout.strip()
                actual = classify(payload)
                assert actual == expected, f"Classifier returned {actual} for freshly encrypted user value {user!r}; expected {expected}"
    finally:
        with open(key_path, "wb") as fp:
            fp.write(original_key)
        os.chmod(key_path, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
