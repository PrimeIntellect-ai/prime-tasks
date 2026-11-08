#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import collections
import json
import os
import re
import signal
import ssl
import subprocess
import time
import urllib.error
import urllib.request

import jwt
import pandas as pd
import pytest


def test_flask_binds_to_localhost():
    app_path = "/app/auth_service/app.py"
    assert os.path.exists(app_path), f"File {app_path} does not exist."

    with open(app_path, "r") as f:
        content = f.read()

    assert "0.0.0.0" not in content, "Flask app is still bound to 0.0.0.0, exposing it to the network."
    assert "127.0.0.1" in content, "Flask app must be explicitly bound to 127.0.0.1."


def test_flask_enforces_hs256():
    app_path = "/app/auth_service/app.py"
    with open(app_path, "r") as f:
        content = f.read()

    assert re.search(r'algorithms\s*=\s*\[\s*[\'"]HS256[\'"]\s*\]', content) or \
           re.search(r"algorithms\s*=\s*\(\s*['\"]HS256['\"]\s*,\s*\)", content), \
           "Flask app does not enforce the HS256 algorithm in jwt.decode."


def test_nginx_ssl_configuration():
    nginx_path = "/app/nginx/nginx.conf"
    assert os.path.exists(nginx_path), f"File {nginx_path} does not exist."

    with open(nginx_path, "r") as f:
        content = f.read()

    assert "443" in content, "Nginx is not configured to listen on port 443."
    assert "ssl_certificate" in content and "/app/certs/server.crt" in content, "Nginx is missing the SSL certificate configuration."
    assert "ssl_certificate_key" in content and "/app/certs/server.key" in content, "Nginx is missing the SSL certificate key configuration."
    assert "proxy_pass" in content and "127.0.0.1:5000" in content, "Nginx is not proxying to 127.0.0.1:5000."


def test_compromised_users_f1_score():
    pred_path = "/home/user/compromised_users.csv"
    true_path = "/root/ground_truth_compromised.csv"

    assert os.path.exists(pred_path), f"Prediction file {pred_path} does not exist."
    assert os.path.exists(true_path), f"Ground truth file {true_path} does not exist."

    try:
        df_pred = pd.read_csv(pred_path)
        assert 'user_id' in df_pred.columns and 'timestamp' in df_pred.columns, "CSV must contain 'user_id' and 'timestamp' columns."
        pred_set = set(zip(df_pred['user_id'].astype(str), df_pred['timestamp'].astype(str)))
    except Exception as e:
        pytest.fail(f"Failed to read or parse predictions: {e}")

    df_true = pd.read_csv(true_path)
    true_set = set(zip(df_true['user_id'].astype(str), df_true['timestamp'].astype(str)))

    tp = len(pred_set.intersection(true_set))
    fp = len(pred_set - true_set)
    fn = len(true_set - pred_set)

    if tp == 0:
        f1 = 0.0
    else:
        precision = tp / (tp + fp)
        recall = tp / (tp + fn)
        f1 = 2 * (precision * recall) / (precision + recall)

    assert f1 >= 0.98, f"F1 score {f1:.4f} is below the required threshold of 0.98."


def _b64(obj):
    raw = json.dumps(obj, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def test_audit_script_executes_and_derives_results():
    script = "/home/user/audit.py"
    log_path = "/app/logs/auth.log"
    output_path = "/home/user/compromised_users.csv"
    assert os.path.isfile(script), f"Audit script {script} does not exist or is not a regular file."

    old_log = open(log_path, "rb").read()
    old_output = open(output_path, "rb").read() if os.path.exists(output_path) else None
    try:
        for trial in range(2):
            nonce = os.urandom(8).hex()
            now = int(time.time()) + trial * 1000
            expected = []
            records = []
            for i in range(13):
                user_id = f"probe_{nonce}_{i}"
                timestamp = now - i * 17
                payload = {"user_id": user_id, "exp": now + 7200, "nonce": nonce}
                if i in (1, 4, 6, 10):
                    token = f'{_b64({"alg": "none", "typ": "JWT"})}.{_b64(payload)}.'
                    expected.append((user_id, str(timestamp)))
                else:
                    token = jwt.encode(payload, "super_secret_key", algorithm="HS256")
                records.append({"timestamp": timestamp, "ip": f"10.{trial}.0.{i + 1}", "token": token})

            with open(log_path, "w") as f:
                for record in records:
                    f.write(json.dumps(record) + "\n")
            if os.path.exists(output_path):
                os.unlink(output_path)

            result = subprocess.run(["python3", script], stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, text=True, timeout=15)
            assert result.returncode == 0, f"audit.py failed: {result.stderr}"
            assert os.path.isfile(output_path), "audit.py did not create compromised_users.csv"
            frame = pd.read_csv(output_path)
            assert list(frame.columns) == ["user_id", "timestamp"], \
                "CSV must contain exactly the columns user_id and timestamp."
            actual = collections.Counter(zip(frame["user_id"].astype(str), frame["timestamp"].astype(str)))
            assert actual == collections.Counter(expected), \
                f"audit.py produced incorrect results for generated log input: {list(actual.elements())}"
    finally:
        with open(log_path, "wb") as f:
            f.write(old_log)
        if old_output is None:
            if os.path.exists(output_path):
                os.unlink(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(old_output)


def _stop_old_services():
    subprocess.run(["nginx", "-s", "stop", "-c", "/app/nginx/nginx.conf"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["redis-cli", "shutdown"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            cmdline = open(f"/proc/{entry}/cmdline", "rb").read().replace(b"\0", b" ")
            if b"/app/auth_service/app.py" in cmdline:
                os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.5)


def _request(token):
    context = ssl._create_unverified_context()
    request = urllib.request.Request("https://127.0.0.1/verify", headers={"Authorization": token})
    try:
        with urllib.request.urlopen(request, context=context, timeout=2) as response:
            return response.status, json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode())


def _port5000_listeners():
    listeners = []
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(path) as f:
            next(f)
            for line in f:
                fields = line.split()
                address, port = fields[1].split(":")
                if int(port, 16) == 5000 and fields[3] == "0A":
                    listeners.append((path, address))
    return listeners


def test_startup_tls_proxy_isolation_and_jwt_behavior():
    start_path = "/app/start.sh"
    assert os.path.isfile(start_path), "/app/start.sh is missing or is not a regular file."
    assert os.access(start_path, os.X_OK), "/app/start.sh is not executable."

    syntax = subprocess.run(["nginx", "-t", "-c", "/app/nginx/nginx.conf"],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert syntax.returncode == 0, f"Nginx configuration is invalid: {syntax.stderr}"

    _stop_old_services()
    process = subprocess.Popen([start_path], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        valid = jwt.encode({"user_id": "runtime_probe", "exp": int(time.time()) + 300},
                           "super_secret_key", algorithm="HS256")
        deadline = time.time() + 15
        last_error = None
        while time.time() < deadline:
            if process.poll() is not None:
                pytest.fail(f"/app/start.sh exited prematurely with status {process.returncode}")
            try:
                status, body = _request(valid)
                if status == 200:
                    break
            except Exception as exc:
                last_error = exc
            time.sleep(0.25)
        else:
            pytest.fail(f"TLS service did not become ready through Nginx: {last_error}")

        assert body.get("status") == "success" and body.get("user") == "runtime_probe", \
            "A correctly signed HS256 token was not accepted through the TLS proxy."

        unsigned_payload = {"user_id": "attacker", "exp": int(time.time()) + 300}
        unsigned = f'{_b64({"alg": "none", "typ": "JWT"})}.{_b64(unsigned_payload)}.'
        status, _ = _request(unsigned)
        assert status == 401, "The API accepted an unsigned alg:none token."

        bad_signature = jwt.encode(unsigned_payload, "wrong_secret", algorithm="HS256")
        status, _ = _request(bad_signature)
        assert status == 401, "The API accepted an HS256 token with an invalid signature."

        listeners = _port5000_listeners()
        assert listeners, "No Flask listener was found on port 5000."
        assert all(path == "/proc/net/tcp" and address == "0100007F" for path, address in listeners), \
            f"Port 5000 is not isolated to IPv4 localhost: {listeners}"
        assert process.poll() is None, "/app/start.sh did not remain running after startup."
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
        subprocess.run(["nginx", "-s", "stop", "-c", "/app/nginx/nginx.conf"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["redis-cli", "shutdown"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
