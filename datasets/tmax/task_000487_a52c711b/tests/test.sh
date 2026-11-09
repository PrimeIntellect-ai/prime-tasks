#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import os
import random
import shutil
import signal
import socket
import string
import subprocess
import time
import urllib.request

import pytest
import redis

ORACLE_PATH = "/app/bin/obfuscated_logger"
AGENT_SCRIPT = "/home/user/clean_logger.py"
NGINX_CONF = "/app/services/nginx/nginx.conf"
WORKER_PATH = "/app/services/backend/worker.py"
VERIFIED_LOGS_PATH = "/home/user/verified_logs.txt"


def generate_random_string(min_len=10, max_len=500):
    chars = string.ascii_letters + string.digits + string.punctuation + " "
    length = random.randint(min_len, max_len)
    return ''.join(random.choice(chars) for _ in range(length))


def expected_logger_output(value):
    md5_hex = hashlib.md5(value.encode()).hexdigest()
    signature = hashlib.sha256(md5_hex.encode()).hexdigest()
    return f"{value}||{signature}\n"


def proc_cmdlines():
    results = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                args = [x.decode(errors='replace') for x in f.read().split(b'\0') if x]
            if args:
                results.append((int(entry), args))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return results


def wait_until(predicate, timeout=8):
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
        raise AssertionError(f"Condition did not become true: {last_error}")
    raise AssertionError("Condition did not become true before timeout")


def test_01_clean_logger_is_independent_and_equivalent():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert not os.path.islink(AGENT_SCRIPT), "clean_logger.py must be an actual auditable Python file"
    assert os.path.isfile(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"

    agent_bytes = open(AGENT_SCRIPT, 'rb').read()
    oracle_bytes = open(ORACLE_PATH, 'rb').read()
    assert agent_bytes != oracle_bytes, "Submission is byte-identical to the reference implementation"

    try:
        source = agent_bytes.decode('utf-8')
    except UnicodeDecodeError as exc:
        pytest.fail(f"clean_logger.py is not UTF-8 Python source: {exc}")

    try:
        tree = ast.parse(source, AGENT_SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f"clean_logger.py is not valid Python source: {exc}")

    allowed_imports = {'sys', 'hashlib', 'argparse'}
    forbidden_calls = {
        'open', 'exec', 'eval', 'compile', '__import__',
        'system', 'popen', 'run', 'call', 'check_call', 'check_output',
        'Popen', 'spawnl', 'spawnlp', 'spawnv', 'spawnvp', 'fork',
        'connect', 'urlopen'
    }
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                assert alias.name.split('.')[0] in allowed_imports, (
                    f"Disallowed dependency in clean implementation: {alias.name}"
                )
        elif isinstance(node, ast.ImportFrom):
            assert node.module and node.module.split('.')[0] in allowed_imports, (
                f"Disallowed dependency in clean implementation: {node.module}"
            )
        elif isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                assert node.func.id not in forbidden_calls, (
                    f"clean_logger.py may not delegate its work via {node.func.id}"
                )
            elif isinstance(node.func, ast.Attribute):
                assert node.func.attr not in forbidden_calls, (
                    f"clean_logger.py may not delegate its work via {node.func.attr}"
                )

    assert '/app/bin/obfuscated_logger' not in source, "clean_logger.py invokes the reference artifact"

    hidden_oracle = ORACLE_PATH + '.verifier-hidden'
    assert not os.path.exists(hidden_oracle)
    os.rename(ORACLE_PATH, hidden_oracle)
    try:
        random.seed(42)
        cases = [
            '', 'a', 'hello world', 'line1\nline2', 'tabs\tand spaces',
            'Grüße 世界 🔐', "quotes'\"`$;&|<>(){}[]", ' ' * 300
        ]
        cases.extend(generate_random_string() for _ in range(1000))

        for i, test_input in enumerate(cases):
            proc = subprocess.run(
                ['python3', AGENT_SCRIPT, test_input],
                capture_output=True,
                text=True,
                timeout=5
            )
            assert proc.returncode == 0, (
                f"Agent script failed on case {i}, input {test_input!r}: {proc.stderr}"
            )
            expected = expected_logger_output(test_input)
            assert proc.stdout == expected, (
                f"Mismatch on case {i}. Input: {test_input!r}; "
                f"expected {expected!r}, got {proc.stdout!r}"
            )
    finally:
        os.rename(hidden_oracle, ORACLE_PATH)


def test_02_required_services_were_started_and_files_were_fixed():
    commands = proc_cmdlines()
    assert any(any('nginx' in arg for arg in args) for _, args in commands), (
        "No running Nginx/OpenResty process was found"
    )
    assert any(any('redis-server' in arg for arg in args) for _, args in commands), (
        "No running Redis server process was found"
    )
    assert any(any('worker.py' in arg and 'backend' in arg for arg in args) for _, args in commands), (
        "The required backend worker.py process is not running"
    )

    r = redis.Redis(host='127.0.0.1', port=6379, decode_responses=True, socket_timeout=2)
    assert r.ping() is True, "Redis is not responding on port 6379"

    nginx_source = open(NGINX_CONF, encoding='utf-8').read()
    worker_source = open(WORKER_PATH, encoding='utf-8').read()

    assert 'listen       8080' in nginx_source or 'listen 8080' in nginx_source
    assert 'content_by_lua' in nginx_source, "Nginx /log must use the local Lua handler"
    assert '127.0.0.1' in nginx_source and '6379' in nginx_source
    assert 'incoming_logs' in nginx_source
    assert '6378' not in nginx_source and 'wrong_logs' not in nginx_source

    assert '127.0.0.1' in worker_source and '6379' in worker_source
    assert 'incoming_logs' in worker_source
    assert VERIFIED_LOGS_PATH in worker_source
    assert '6378' not in worker_source and 'wrong_logs' not in worker_source

    parsed_worker = ast.parse(worker_source, WORKER_PATH)
    assert any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == 'brpop'
        for node in ast.walk(parsed_worker)
    ), "Backend worker must pop queued logs with Redis BRPOP"


def stop_existing_services():
    subprocess.run(['redis-cli', '-p', '6379', 'shutdown', 'nosave'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['nginx', '-s', 'stop', '-c', NGINX_CONF], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['pkill', '-f', '/app/services/backend/worker.py'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['pkill', '-x', 'nginx'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)
    fuser = shutil.which('fuser')
    assert fuser, "fuser is required to isolate the configured services"
    subprocess.run([fuser, '-k', '8080/tcp'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([fuser, '-k', '6379/tcp'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)


def post(body):
    req = urllib.request.Request(
        'http://localhost:8080/log',
        data=body.encode('utf-8'),
        method='POST'
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.status in (200, 201, 202, 204)
        return response.read()


def test_03_real_nginx_redis_worker_flow():
    stop_existing_services()

    redis_proc = subprocess.run(
        ['redis-server', '--bind', '127.0.0.1', '--port', '6379', '--daemonize', 'yes'],
        capture_output=True,
        text=True
    )
    assert redis_proc.returncode == 0, redis_proc.stderr

    r = redis.Redis(host='127.0.0.1', port=6379, decode_responses=True, socket_timeout=2)
    wait_until(lambda: r.ping() is True)
    r.flushall()

    config_test = subprocess.run(
        ['nginx', '-t', '-c', NGINX_CONF], capture_output=True, text=True
    )
    assert config_test.returncode == 0, config_test.stdout + config_test.stderr
    nginx_start = subprocess.run(
        ['nginx', '-c', NGINX_CONF], capture_output=True, text=True
    )
    assert nginx_start.returncode == 0, nginx_start.stdout + nginx_start.stderr

    def nginx_listening():
        try:
            with socket.create_connection(('127.0.0.1', 8080), timeout=0.5):
                return True
        except OSError:
            return False
    wait_until(nginx_listening)

    if os.path.exists(VERIFIED_LOGS_PATH):
        os.remove(VERIFIED_LOGS_PATH)

    random.seed(123)
    test_messages = [generate_random_string(20, 50) for _ in range(5)]

    # With no worker running, POSTs must appear in the required Redis list.
    for msg in test_messages:
        post(msg)
    queued = r.lrange('incoming_logs', 0, -1)
    assert queued == list(reversed(test_messages)), (
        f"Nginx Lua did not LPUSH raw bodies to incoming_logs: {queued!r}"
    )
    assert r.llen('wrong_logs') == 0

    worker = subprocess.Popen(
        ['python3', WORKER_PATH],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    try:
        def first_batch_written():
            if not os.path.exists(VERIFIED_LOGS_PATH):
                return False
            with open(VERIFIED_LOGS_PATH, encoding='utf-8') as f:
                return f.read().splitlines() == test_messages
        wait_until(first_batch_written)
        assert r.llen('incoming_logs') == 0

        # Exercise the complete requested path using actual clean_logger output.
        raw_message = 'end-to-end-' + generate_random_string(25, 40)
        logger = subprocess.run(
            ['python3', AGENT_SCRIPT, raw_message],
            capture_output=True,
            text=True,
            timeout=5
        )
        assert logger.returncode == 0, logger.stderr
        transformed = logger.stdout.rstrip('\n')
        assert transformed == expected_logger_output(raw_message).rstrip('\n')
        post(transformed)

        expected_lines = test_messages + [transformed]
        def complete_batch_written():
            if not os.path.exists(VERIFIED_LOGS_PATH):
                return False
            with open(VERIFIED_LOGS_PATH, encoding='utf-8') as f:
                return f.read().splitlines() == expected_lines
        wait_until(complete_batch_written)
    finally:
        worker.terminate()
        try:
            worker.wait(timeout=3)
        except subprocess.TimeoutExpired:
            worker.kill()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
