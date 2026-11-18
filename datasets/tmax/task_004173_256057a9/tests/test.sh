#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import socket
import subprocess
import time
import uuid

import jwt


def run_command(args, timeout=10):
    return subprocess.run(
        args,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def test_tls_certificates_exist():
    cert_path = "/app/nginx/ssl/cert.pem"
    key_path = "/app/nginx/ssl/key.pem"
    assert os.path.isfile(cert_path), f"TLS certificate missing: {cert_path}"
    assert os.path.isfile(key_path), f"TLS private key missing: {key_path}"
    assert os.path.getsize(cert_path) > 0, f"TLS certificate is empty: {cert_path}"
    assert os.path.getsize(key_path) > 0, f"TLS private key is empty: {key_path}"

    cert_check = run_command(["openssl", "x509", "-in", cert_path, "-noout", "-checkend", "0"])
    assert cert_check.returncode == 0, f"Invalid or expired TLS certificate: {cert_check.stderr}"

    key_check = run_command(["openssl", "pkey", "-in", key_path, "-noout"])
    assert key_check.returncode == 0, f"Invalid TLS private key: {key_check.stderr}"

    cert_pub = run_command(["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"])
    key_pub = run_command(["openssl", "pkey", "-in", key_path, "-pubout"])
    assert cert_pub.returncode == 0 and key_pub.returncode == 0
    assert cert_pub.stdout.strip() == key_pub.stdout.strip(), "TLS certificate and private key do not match"

    identity = run_command([
        "openssl", "x509", "-in", cert_path, "-noout", "-subject", "-issuer", "-nameopt", "RFC2253"
    ])
    assert identity.returncode == 0
    lines = [line.strip() for line in identity.stdout.splitlines() if line.strip()]
    assert len(lines) == 2
    subject = lines[0].split("=", 1)[1]
    issuer = lines[1].split("=", 1)[1]
    assert subject == issuer, "TLS certificate is not self-signed"


def test_nginx_proxy_configuration():
    conf_path = "/app/nginx/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx config missing: {conf_path}"
    with open(conf_path, "r") as f:
        content = f.read()
    assert "http://127.0.0.1:5000" in content, "Nginx config does not proxy to the correct Flask port (5000)."

    syntax = run_command(["nginx", "-t", "-c", conf_path])
    assert syntax.returncode == 0, f"Nginx configuration is invalid: {syntax.stderr}"


def curl_health():
    result = run_command([
        "curl", "-ksS", "--max-time", "2", "-w", "\\n%{http_code}",
        "https://127.0.0.1:8443/api/health"
    ], timeout=4)
    if result.returncode != 0 or "\n" not in result.stdout:
        return None, None
    body, status = result.stdout.rsplit("\n", 1)
    return body, status.strip()


def test_services_start_and_health_is_really_proxied():
    subprocess.run(["pkill", "-9", "-x", "nginx"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-9", "-f", "/app/flask/app.py"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-9", "-x", "redis-server"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)

    started = run_command(["bash", "/app/start_services.sh"], timeout=15)
    assert started.returncode == 0, f"Service startup failed:\n{started.stdout}\n{started.stderr}"

    body = status = None
    for _ in range(20):
        body, status = curl_health()
        if status == "200":
            break
        time.sleep(0.25)
    assert status == "200", f"HTTPS health endpoint did not return 200 (status={status}, body={body!r})"
    try:
        payload = json.loads(body)
    except Exception as exc:
        raise AssertionError(f"Health endpoint did not return JSON: {body!r}") from exc
    assert payload.get("status") == "ok", f"Unexpected Flask health response: {payload!r}"

    # Replace Flask temporarily with an unpredictable backend response. This proves
    # that Nginx actually forwards /api/health to port 5000 rather than fabricating
    # a fixed successful response.
    subprocess.run(["pkill", "-9", "-f", "/app/flask/app.py"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.4)
    nonce = secrets.token_hex(24)
    server_code = r'''
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
nonce = sys.argv[1]
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/api/health":
            self.send_response(404); self.end_headers(); return
        data = json.dumps({"proxy_nonce": nonce}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *args):
        pass
HTTPServer(("127.0.0.1", 5000), Handler).serve_forever()
'''
    backend = subprocess.Popen(
        ["python3", "-c", server_code, nonce],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        ready = False
        for _ in range(20):
            if backend.poll() is not None:
                break
            try:
                with socket.create_connection(("127.0.0.1", 5000), timeout=0.2):
                    ready = True
                    break
            except OSError:
                time.sleep(0.15)
        backend_error = ""
        if backend.poll() is not None and backend.stderr:
            backend_error = backend.stderr.read()
        assert ready, f"Could not start verifier backend on Flask port: {backend_error}"

        proxied_body = proxied_status = None
        for _ in range(10):
            proxied_body, proxied_status = curl_health()
            if proxied_status == "200" and nonce in (proxied_body or ""):
                break
            time.sleep(0.2)
        assert proxied_status == "200", f"Proxied challenge returned status {proxied_status}"
        assert json.loads(proxied_body) == {"proxy_nonce": nonce}, "Nginx did not proxy the request to port 5000"
    finally:
        backend.terminate()
        try:
            backend.wait(timeout=3)
        except subprocess.TimeoutExpired:
            backend.kill()


def test_attacker_ip_extracted():
    ip_path = "/home/user/attacker_ip.txt"
    assert os.path.isfile(ip_path), f"Attacker IP file missing: {ip_path}"
    with open(ip_path, "r") as f:
        ip = f.read().strip()
    assert ip == "10.13.37.99", f"Incorrect attacker IP extracted. Expected '10.13.37.99', got '{ip}'"


def test_jwt_filter_adversarial_corpus():
    script_path = "/home/user/jwt_filter.py"
    assert os.path.isfile(script_path), f"JWT filter script missing: {script_path}"

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"
    clean_out = "/tmp/clean_out.json"
    evil_out = "/tmp/evil_out.json"
    for path in (clean_out, evil_out):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    clean_run = subprocess.run(["python3", script_path, clean_dir, clean_out], check=False)
    evil_run = subprocess.run(["python3", script_path, evil_dir, evil_out], check=False)
    assert clean_run.returncode == 0, "JWT filter failed while processing clean corpus"
    assert evil_run.returncode == 0, "JWT filter failed while processing evil corpus"

    assert os.path.isfile(clean_out), f"Output JSON for clean corpus missing: {clean_out}"
    assert os.path.isfile(evil_out), f"Output JSON for evil corpus missing: {evil_out}"

    with open(clean_out, "r") as f:
        clean_results = json.load(f)
    with open(evil_out, "r") as f:
        evil_results = json.load(f)

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    for cf in clean_files:
        if not clean_results.get(cf, False):
            clean_failed.append(cf)

    evil_bypassed = []
    for ef in evil_files:
        if evil_results.get(ef, True):
            evil_bypassed.append(ef)

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")

    assert not errors, "JWT Filter failed corpus validation:\n" + "\n".join(errors)


def b64url_json(value):
    raw = json.dumps(value, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def test_jwt_filter_randomized_mixed_corpus(tmp_path):
    script_path = "/home/user/jwt_filter.py"
    secret = "Secret-Responder-Key-99!"
    now = int(time.time())
    corpus = tmp_path / ("inputs_" + uuid.uuid4().hex)
    corpus.mkdir()

    cases = []
    cases.append((jwt.encode({"sub": uuid.uuid4().hex, "exp": now + 900}, secret, algorithm="HS256"), True))
    cases.append((jwt.encode({"user": secrets.token_hex(9), "iat": now - 2, "exp": now + 1800}, secret, algorithm="HS256"), True))
    cases.append((jwt.encode({"sub": uuid.uuid4().hex, "exp": now - 60}, secret, algorithm="HS256"), False))
    cases.append((jwt.encode({"sub": uuid.uuid4().hex, "exp": now + 900}, secrets.token_hex(20), algorithm="HS256"), False))
    cases.append((jwt.encode({"sub": uuid.uuid4().hex, "exp": now + 900}, secret, algorithm="HS384"), False))
    cases.append((jwt.encode({"sub": uuid.uuid4().hex, "nbf": now + 600, "exp": now + 1200}, secret, algorithm="HS256"), False))

    none_payload = {"sub": uuid.uuid4().hex, "exp": now + 900}
    cases.append((b64url_json({"alg": "none", "typ": "JWT"}) + "." + b64url_json(none_payload) + ".", False))
    cases.append((b64url_json({"alg": "NoNe", "typ": "JWT"}) + "." + b64url_json(none_payload) + ".", False))
    cases.append(("not-a-jwt-" + secrets.token_urlsafe(18), False))

    expected = {}
    for token, verdict in cases:
        filename = uuid.uuid4().hex + ".token"
        (corpus / filename).write_text(token)
        expected[filename] = verdict

    output = tmp_path / ("result_" + uuid.uuid4().hex + ".json")
    result = run_command(["python3", script_path, str(corpus), str(output)], timeout=15)
    assert result.returncode == 0, f"JWT filter exited unsuccessfully: {result.stderr}"
    assert output.is_file(), "JWT filter did not create output for randomized corpus"

    with output.open() as f:
        actual = json.load(f)
    assert isinstance(actual, dict), "JWT filter output must be a JSON dictionary"
    assert set(actual) == set(expected), "JWT filter output keys do not exactly match input filenames"
    assert all(type(value) is bool for value in actual.values()), "JWT filter verdicts must be JSON booleans"
    assert actual == expected, f"JWT filter misclassified randomized tokens: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
