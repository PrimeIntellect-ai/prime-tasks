#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import re
import socket
import subprocess
import sys
import time
import urllib.request
import uuid

import pytest
import redis


def compute_f1(pred_file, truth_file):
    with open(pred_file, 'r') as f:
        preds = {line.strip() for line in f if line.strip()}
    with open(truth_file, 'r') as f:
        truths = {line.strip() for line in f if line.strip()}

    tp = len(preds.intersection(truths))
    fp = len(preds - truths)
    fn = len(truths - preds)
    if tp == 0:
        return 0.0
    precision = tp / (tp + fp)
    recall = tp / (tp + fn)
    return 2 * precision * recall / (precision + recall)


def wait_for(predicate, timeout=8.0):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            if predicate():
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    if last_error:
        raise AssertionError(f"Timed out waiting for condition: {last_error}")
    raise AssertionError("Timed out waiting for condition")


def terminate(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=3)


def test_token_extraction_f1_score():
    pred_file = '/app/compromised_tokens.txt'
    truth_file = '/tests/.hidden_truth.txt'

    assert os.path.isfile(pred_file), f"Prediction file {pred_file} is missing."
    assert os.path.isfile(truth_file), f"Truth file {truth_file} is missing."

    f1 = compute_f1(pred_file, truth_file)
    threshold = 0.95
    assert f1 >= threshold, f"F1 Score {f1:.4f} is below the threshold of {threshold}."


def test_ssh_hardening_password_disabled():
    sshd_config_path = '/app/sshd_config'
    assert os.path.isfile(sshd_config_path), f"{sshd_config_path} is missing."

    with open(sshd_config_path, 'r') as f:
        content = f.read()

    lines = [line.strip() for line in content.splitlines()]
    active_lines = [line for line in lines if not line.startswith('#') and line]
    password_auth_directives = [line for line in active_lines if line.startswith('PasswordAuthentication')]

    assert len(password_auth_directives) > 0, "PasswordAuthentication directive missing in active config."
    assert all('no' in line for line in password_auth_directives), "PasswordAuthentication is not set to 'no'."


def test_ssh_hardening_key_generated_and_authorized():
    priv_key_path = '/home/user/.ssh/admin_key'
    pub_key_path = '/home/user/.ssh/admin_key.pub'
    auth_keys_path = '/home/user/.ssh/authorized_keys'

    assert os.path.isfile(priv_key_path), f"Private key {priv_key_path} is missing."
    assert os.path.isfile(pub_key_path), f"Public key {pub_key_path} is missing."
    assert os.path.isfile(auth_keys_path), f"Authorized keys file {auth_keys_path} is missing."

    with open(pub_key_path, 'r') as f:
        pub_key_content = f.read().strip()
    with open(auth_keys_path, 'r') as f:
        auth_keys_content = f.read()

    pub_key_parts = pub_key_content.split()
    if len(pub_key_parts) >= 2:
        key_body = pub_key_parts[1]
        assert key_body in auth_keys_content, "The generated admin_key is not in authorized_keys."
    else:
        assert pub_key_content in auth_keys_content, "The generated admin_key is not in authorized_keys."


def test_architecture_remediation_no_token_args():
    api_path = '/app/api.py'
    worker_path = '/app/worker.py'

    assert os.path.isfile(api_path), f"{api_path} is missing."
    assert os.path.isfile(worker_path), f"{worker_path} is missing."

    with open(api_path, 'r') as f:
        api_content = f.read()
    with open(worker_path, 'r') as f:
        worker_content = f.read()

    assert '--token' not in api_content, f"--token argument is still present in {api_path}."
    assert '--token' not in worker_content, f"--token argument is still present in {worker_path}."


def test_architecture_remediation_redis_usage():
    api_path = '/app/api.py'
    worker_path = '/app/worker.py'

    with open(api_path, 'r') as f:
        api_content = f.read().lower()
    with open(worker_path, 'r') as f:
        worker_content = f.read().lower()

    assert 'redis' in api_content, f"Redis is not being used in {api_path}."
    assert 'redis' in worker_content, f"Redis is not being used in {worker_path}."
    assert 'auth_tasks' in api_content, f"'auth_tasks' list not referenced in {api_path}."
    assert 'auth_tasks' in worker_content, f"'auth_tasks' list not referenced in {worker_path}."


def test_functional_nginx_flask_redis_worker_flow():
    redis_proc = None
    api_proc = None
    nginx_proc = None
    worker_proc = None
    client = redis.Redis(host='127.0.0.1', port=6379, decode_responses=True)

    try:
        try:
            client.ping()
        except Exception:
            redis_proc = subprocess.Popen(
                ['redis-server', '--bind', '127.0.0.1', '--port', '6379', '--save', '', '--appendonly', 'no'],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            wait_for(lambda: client.ping())

        client.delete('auth_tasks')

        config_check = subprocess.run(
            ['nginx', '-t', '-c', '/app/nginx.conf'],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        assert config_check.returncode == 0, config_check.stdout

        runner = '/tmp/run_submitted_api.py'
        with open(runner, 'w') as f:
            f.write(
                "import importlib.util\n"
                "spec = importlib.util.spec_from_file_location('submitted_api', '/app/api.py')\n"
                "mod = importlib.util.module_from_spec(spec)\n"
                "spec.loader.exec_module(mod)\n"
                "assert hasattr(mod, 'app')\n"
                "mod.app.run(host='127.0.0.1', port=15000, use_reloader=False)\n"
            )

        api_proc = subprocess.Popen(
            [sys.executable, runner],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        def api_listening():
            with socket.create_connection(('127.0.0.1', 15000), timeout=0.2):
                return True

        wait_for(api_listening)
        assert api_proc.poll() is None, "Submitted Flask API exited unexpectedly."

        nginx_config = '/tmp/submitted_flow_nginx.conf'
        with open(nginx_config, 'w') as f:
            f.write(
                "worker_processes 1;\n"
                "pid /tmp/submitted_flow_nginx.pid;\n"
                "error_log /tmp/submitted_flow_nginx_error.log;\n"
                "events { worker_connections 128; }\n"
                "http { server { listen 127.0.0.1:18080; location / { proxy_pass http://127.0.0.1:15000; } } }\n"
            )

        nginx_proc = subprocess.Popen(
            ['nginx', '-c', nginx_config, '-g', 'daemon off;'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        def nginx_listening():
            with socket.create_connection(('127.0.0.1', 18080), timeout=0.2):
                return True

        wait_for(nginx_listening)
        request = urllib.request.Request('http://127.0.0.1:18080/generate_task', data=b'', method='POST')
        with urllib.request.urlopen(request, timeout=5) as response:
            assert response.status == 200
            response.read()

        wait_for(lambda: client.llen('auth_tasks') == 1)
        generated_token = client.lindex('auth_tasks', 0)
        assert generated_token is not None
        assert re.fullmatch(r'SEC-[0-9a-fA-F]{32}', generated_token), "API did not enqueue the generated secure token."

        for pid in os.listdir('/proc'):
            if not pid.isdigit():
                continue
            try:
                with open(f'/proc/{pid}/cmdline', 'rb') as f:
                    cmdline = f.read().replace(b'\x00', b' ').decode(errors='ignore')
            except (FileNotFoundError, PermissionError, ProcessLookupError):
                continue
            assert generated_token not in cmdline, "Generated token was exposed in process arguments."

        worker_proc = subprocess.Popen(
            [sys.executable, '/app/worker.py'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        wait_for(lambda: client.llen('auth_tasks') == 0)
        assert worker_proc.poll() is None, "Worker exited instead of remaining a continuous daemon."

        marker = 'SEC-' + uuid.uuid4().hex
        client.rpush('auth_tasks', marker)
        wait_for(lambda: client.llen('auth_tasks') == 0)
        time.sleep(0.3)
        assert worker_proc.poll() is None, "Worker did not continue waiting for additional tasks."

        with open(f'/proc/{worker_proc.pid}/cmdline', 'rb') as f:
            worker_cmdline = f.read().replace(b'\x00', b' ').decode(errors='ignore')
        assert '--token' not in worker_cmdline
        assert generated_token not in worker_cmdline
        assert marker not in worker_cmdline
    finally:
        terminate(worker_proc)
        terminate(nginx_proc)
        terminate(api_proc)
        if redis_proc is not None:
            terminate(redis_proc)
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
