#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import hashlib
import secrets
import random
import pytest

SCRIPT_PATH = "/home/user/detect_redirects.py"


def run_detector(log_path):
    assert os.path.isfile(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} to exist."
    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, str(log_path)],
            capture_output=True,
            text=True,
            check=True,
            timeout=15
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script {SCRIPT_PATH} failed to execute with exit code {e.returncode}. Stderr: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Script {SCRIPT_PATH} timed out during execution.")

    try:
        predicted_list = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Script output is not valid JSON. Output was: {result.stdout[:100]}...")

    assert isinstance(predicted_list, list), "Script output is valid JSON but not an array."
    assert all(isinstance(item, str) for item in predicted_list), "Every item in the JSON array must be a string."
    return set(predicted_list)


def assert_f1(predicted, truth):
    tp = len(predicted & truth)
    fp = len(predicted - truth)
    fn = len(truth - predicted)
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0
    assert f1 >= 0.90, (
        f"F1 score {f1:.4f} is below the threshold of 0.90. "
        f"(Precision: {precision:.4f}, Recall: {recall:.4f})"
    )


def test_new_hash_correctness():
    hash_path = "/home/user/new_hash.txt"
    assert os.path.isfile(hash_path), f"Expected file {hash_path} to exist."

    with open(hash_path, "r") as f:
        actual_hash = f.read().strip()

    expected_string = "old_pwd_MasterSecr3t!_RotateMeNow2024!"
    expected_hash = hashlib.sha256(expected_string.encode()).hexdigest()

    assert actual_hash == expected_hash, f"Hash in {hash_path} is incorrect. Expected exact SHA256 hex digest of the required string."


def test_detect_redirects_f1_score():
    log_path = "/app/hidden_test.log"
    assert os.path.isfile(log_path), f"Expected log file {log_path} to exist."
    predicted = run_detector(log_path)

    # The hidden truth IPs as defined in the task setup
    truth = {"10.0.0.5", "192.168.1.100", "172.16.0.4"}
    assert_f1(predicted, truth)


def unique_ip(used):
    while True:
        ip = f"198.18.{secrets.randbelow(255)}.{secrets.randbelow(254) + 1}"
        if ip not in used:
            used.add(ip)
            return ip


def build_held_out_log(path, used):
    token = secrets.token_hex(10)
    domain = f"{token}.example.net"
    malicious_targets = [
        f"/login?next=http://{domain}/landing",
        f"/login?next=https://{domain}/landing",
        f"/login?return_to=//{domain}/collect",
        f"/login?redirect=http://{domain}/go",
        f"/login?x=1&next=https://{domain}/after",
        f"/login?return_to=HTTP://{domain}/upper",
        f"/login?redirect=HtTpS://{domain}/mixed",
        f"/login?next=http%3A%2F%2F{domain}%2Fencoded",
        f"/login?return_to=%2F%2F{domain}%2Fencoded",
        f"/login?redirect=https://{domain}/path?item=1",
        f"/login?next=https://user@{domain}/private",
        f"/login?return_to=http://{domain}:8080/service",
    ]
    benign_targets = [
        "/login?next=/dashboard",
        "/login?return_to=/account/settings",
        "/login?redirect=/",
        "/login?next=dashboard",
        "/login?next=./dashboard",
        "/login?next=../home",
        "/login?next=%2Fdashboard",
        "/login?return_to=/account%3Ftab%3D1",
        "/login?next=/safe&return_to=/also-safe",
        "/login?redirect=",
        f"/login?url=http://{domain}/not-a-redirect-parameter",
        f"/search?next=http://{domain}/not-login",
        f"/login-help?redirect=https://{domain}/not-login",
        "/login",
        "/login?next=profile",
        "/login?return_to=orders/123",
        "/assets/login.js?next=http://example.net",
        "/logout?redirect=//example.net",
    ]

    rows = []
    truth = set()
    for target in malicious_targets:
        ip = unique_ip(used)
        truth.add(ip)
        rows.append((ip, target, 302))
    for target in benign_targets:
        rows.append((unique_ip(used), target, 200))

    random.SystemRandom().shuffle(rows)
    with open(path, "w") as f:
        for ip, target, status in rows:
            f.write(
                f'{ip} - - [11/Sep/2026:12:34:56 +0000] '
                f'"GET {target} HTTP/1.1" {status} 154 "-" "held-out/{token}"\n'
            )
    return truth


def test_detect_redirects_generated_held_out_logs(tmp_path):
    used = set()
    for index in range(2):
        log_path = tmp_path / f"held_out_{index}.log"
        truth = build_held_out_log(log_path, used)
        predicted = run_detector(log_path)
        assert_f1(predicted, truth)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
