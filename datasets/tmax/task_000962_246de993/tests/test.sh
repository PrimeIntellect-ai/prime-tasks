#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import ipaddress
import json
import os
import secrets
import socket
import subprocess
import tempfile
import urllib.error
import urllib.request


def calculate_f1(truth, pred):
    tp = len(truth & pred)
    fp = len(pred - truth)
    fn = len(truth - pred)
    if tp == 0:
        return 0.0
    precision = tp / (tp + fp)
    recall = tp / (tp + fn)
    return 2 * precision * recall / (precision + recall)


def fetch(url, token):
    request = urllib.request.Request(url, headers={"Authorization": token})
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode()


def test_service_composition():
    nginx_path = "/home/user/app/nginx/nginx.conf"
    flask_config_path = "/home/user/app/flask/config.py"
    assert os.path.isfile(nginx_path), "Nginx configuration is missing"
    assert os.path.isfile(flask_config_path), "Flask configuration is missing"

    with open(nginx_path) as config_file:
        nginx_config = " ".join(config_file.read().split())
    assert "listen 8080;" in nginx_config, "Nginx is not configured to listen on port 8080"
    assert "proxy_pass http://127.0.0.1:5000;" in nginx_config, "Nginx does not proxy to the local Flask backend"

    nginx_test = subprocess.run(
        ["nginx", "-t", "-c", nginx_path], capture_output=True, text=True, timeout=10
    )
    assert nginx_test.returncode == 0, nginx_test.stderr

    spec = importlib.util.spec_from_file_location("submitted_flask_config", flask_config_path)
    flask_config = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(flask_config)
    assert flask_config.REDIS_HOST == "127.0.0.1", "Flask REDIS_HOST is not local"
    assert flask_config.REDIS_PORT == 6379, "Flask REDIS_PORT is not 6379"

    redis_result = subprocess.run(
        ["redis-cli", "-h", "127.0.0.1", "-p", "6379", "PING"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert redis_result.returncode == 0 and redis_result.stdout.strip() == "PONG", "Redis is not running on port 6379"

    marker = secrets.token_hex(8)
    direct_status, direct_body = fetch(
        f"http://127.0.0.1:5000/verifier/{marker}", "Bearer valid_token"
    )
    assert direct_status == 200, "Flask is not running on port 5000"
    assert json.loads(direct_body).get("path") == f"verifier/{marker}"

    proxy_status, proxy_body = fetch(
        f"http://127.0.0.1:8080/verifier/{marker}", "Bearer valid_token"
    )
    assert proxy_status == 200, "Nginx is not running or is not proxying to Flask"
    assert json.loads(proxy_body).get("path") == f"verifier/{marker}"

    unauthorized_status, _ = fetch(
        f"http://127.0.0.1:8080/verifier/{marker}", "Bearer invalid_token"
    )
    assert unauthorized_status == 401, "Backend authorization responses are not passing through Nginx"


def create_eval_data():
    rng = secrets.SystemRandom()
    used = set()

    def new_ip():
        while True:
            candidate = f"10.{rng.randrange(1, 255)}.{rng.randrange(0, 256)}.{rng.randrange(1, 255)}"
            if candidate not in used:
                used.add(candidate)
                return candidate

    traversal_plain = new_ip()
    traversal_encoded = new_ip()
    sqli = new_ip()
    command_rm = new_ip()
    command_substitution = new_ip()
    excessive_401 = new_ip()
    truth_ips = {
        traversal_plain,
        traversal_encoded,
        sqli,
        command_rm,
        command_substitution,
        excessive_401,
    }

    logs = [
        f'{traversal_plain} - - [10/Oct/2023:13:55:36 -0700] "GET /api/data?file=../../etc/passwd HTTP/1.1" 200 512 "-" "curl/7.68.0"',
        f'{traversal_encoded} - - [10/Oct/2023:13:55:36 -0700] "GET /api/data?file=%2e%2e%2fetc/passwd HTTP/1.1" 200 512 "-" "curl/7.68.0"',
        f'{sqli} - - [10/Oct/2023:13:55:37 -0700] "GET /api/data?id=1%20UNION%20SELECT%201,2,3 HTTP/1.1" 200 512 "-" "curl/7.68.0"',
        f'{command_rm} - - [10/Oct/2023:13:55:38 -0700] "GET /api/data?cmd=;%20rm%20-rf%20/ HTTP/1.1" 200 512 "-" "curl/7.68.0"',
        f'{command_substitution} - - [10/Oct/2023:13:55:38 -0700] "GET /api/data?cmd=$(whoami) HTTP/1.1" 200 512 "-" "curl/7.68.0"',
    ]

    for _ in range(55):
        logs.append(f'{excessive_401} - - [10/Oct/2023:13:55:39 -0700] "GET /api/data HTTP/1.1" 401 128 "-" "curl/7.68.0"')

    ordinary = [new_ip() for _ in range(100)]
    exactly_fifty = new_ip()
    fewer_than_fifty = new_ip()
    legitimate_single = new_ip()

    for _ in range(50):
        logs.append(f'{exactly_fifty} - - [10/Oct/2023:13:55:40 -0700] "GET /api/data HTTP/1.1" 401 128 "-" "curl/7.68.0"')
    for _ in range(10):
        logs.append(f'{fewer_than_fifty} - - [10/Oct/2023:13:55:41 -0700] "GET /api/data HTTP/1.1" 401 128 "-" "curl/7.68.0"')
    logs.append(f'{legitimate_single} - - [10/Oct/2023:13:55:42 -0700] "GET /api/data HTTP/1.1" 200 512 "-" "curl/7.68.0"')

    while len(logs) < 5000:
        ip = rng.choice(ordinary)
        status = rng.choice([200, 200, 200, 404])
        logs.append(f'{ip} - - [10/Oct/2023:13:55:43 -0700] "GET /api/data HTTP/1.1" {status} 512 "-" "curl/7.68.0"')

    rng.shuffle(logs)
    handle = tempfile.NamedTemporaryFile(mode="w", prefix="ids-eval-", suffix=".log", delete=False)
    try:
        handle.write("\n".join(logs) + "\n")
        return handle.name, truth_ips
    finally:
        handle.close()


def test_ids_filter_f1_score():
    script_path = "/home/user/ids_filter.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    log_path, truth_ips = create_eval_data()
    try:
        result = subprocess.run([script_path, log_path], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, f"Script failed with error: {result.stderr}"

        with open("/home/user/predictions.txt", "w") as prediction_file:
            prediction_file.write(result.stdout)

        output_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        assert len(output_lines) == len(set(output_lines)), "Output contains duplicate IP addresses"
        for value in output_lines:
            try:
                ipaddress.ip_address(value)
            except ValueError:
                raise AssertionError(f"Output contains a non-IP value: {value}")

        pred_ips = set(output_lines)
        f1 = calculate_f1(truth_ips, pred_ips)
        assert f1 >= 0.95, f"F1 score {f1:.4f} is below the threshold of 0.95. Truth: {truth_ips}, Pred: {pred_ips}"
    finally:
        os.unlink(log_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
