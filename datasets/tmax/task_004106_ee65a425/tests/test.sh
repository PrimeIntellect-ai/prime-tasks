#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import socket
import string
import subprocess
import urllib.error
import urllib.request

import pytest


def socket_owner_pids(inodes):
    owners = set()
    targets = {f"socket:[{inode}]" for inode in inodes}
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        fd_dir = f'/proc/{pid}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in targets:
                        owners.add(pid)
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return owners


def unix_socket_inodes(path):
    inodes = set()
    with open('/proc/net/unix') as f:
        next(f, None)
        for line in f:
            fields = line.split()
            if len(fields) >= 8 and fields[-1] == path:
                inodes.add(fields[6])
    return inodes


def tcp_listener_inodes(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == '0A':
                        if int(fields[1].split(':')[1], 16) == port:
                            inodes.add(fields[9])
        except OSError:
            pass
    return inodes


def oracle_token(username):
    oracle_script = '/tests/oracle_token.py'
    assert os.path.exists(oracle_script), f"Oracle script {oracle_script} is missing."
    result = subprocess.run(
        ['python3', oracle_script, username],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def test_config_json_corrected():
    """Verify that the configuration file has been properly restored."""
    config_path = '/app/config.json'
    assert os.path.exists(config_path), f"Config file {config_path} is missing."

    try:
        with open(config_path, 'r') as f:
            config_data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Config file {config_path} is not valid JSON.")

    assert config_data.get('REDIS_HOST') == '127.0.0.1', (
        f"Expected REDIS_HOST to be '127.0.0.1', got {config_data.get('REDIS_HOST')}"
    )
    assert config_data.get('REDIS_PORT') == 6379, (
        f"Expected REDIS_PORT to be 6379, got {config_data.get('REDIS_PORT')}"
    )
    assert config_data.get('AUTH_SOCKET') == '/tmp/auth.sock', (
        f"Expected AUTH_SOCKET to be '/tmp/auth.sock', got {config_data.get('AUTH_SOCKET')}"
    )


def test_api_gateway_end_to_end():
    """Verify that the specified services are running and cooperating end to end."""
    redis_result = subprocess.run(
        ['redis-cli', '-h', '127.0.0.1', '-p', '6379', 'PING'],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert redis_result.returncode == 0 and redis_result.stdout.strip() == 'PONG', (
        f"Redis is not responding on 127.0.0.1:6379: {redis_result.stderr}"
    )

    auth_inodes = unix_socket_inodes('/tmp/auth.sock')
    assert auth_inodes, 'No process is listening on /tmp/auth.sock.'
    auth_pids = socket_owner_pids(auth_inodes)
    assert any(
        os.path.realpath(f'/proc/{pid}/exe') == '/app/auth_daemon'
        for pid in auth_pids
        if os.path.exists(f'/proc/{pid}/exe')
    ), '/tmp/auth.sock is not owned by the supplied /app/auth_daemon binary.'

    gateway_inodes = tcp_listener_inodes(5000)
    assert gateway_inodes, 'No process is listening on TCP port 5000.'
    gateway_pids = socket_owner_pids(gateway_inodes)
    gateway_is_real = False
    for pid in gateway_pids:
        try:
            with open(f'/proc/{pid}/cmdline', 'rb') as f:
                argv = f.read().split(b'\0')
            if b'/app/api_gateway.py' in argv:
                gateway_is_real = True
                break
        except OSError:
            pass
    assert gateway_is_real, 'Port 5000 is not served by /app/api_gateway.py.'

    username = 'testuser'
    url = 'http://127.0.0.1:5000/auth'
    payload = json.dumps({'username': username}).encode('utf-8')
    req = urllib.request.Request(
        url,
        data=payload,
        headers={'Content-Type': 'application/json'},
    )

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            response_body = response.read().decode('utf-8')
            try:
                data = json.loads(response_body)
            except json.JSONDecodeError:
                pytest.fail(f"API Gateway did not return valid JSON. Got: {response_body}")

            assert 'token' in data, f"Response JSON missing 'token' key. Got: {data}"
            assert len(data['token']) > 0, 'Returned token is empty.'
            assert data['token'] == oracle_token(username), (
                'The API gateway did not return the compromised daemon token.'
            )
    except urllib.error.URLError as e:
        pytest.fail(
            f"Failed to connect to API Gateway at {url}. Are the services running? Error: {e}"
        )


def test_backdoor_token_fuzz_equivalence():
    """Fuzz test the student's Python script against the protected oracle."""
    agent_script = '/home/user/backdoor_token.py'
    oracle_script = '/tests/oracle_token.py'

    assert os.path.exists(agent_script), f"Agent script {agent_script} is missing."
    assert os.path.isfile(agent_script), f"Agent script {agent_script} is not a regular file."
    assert os.path.exists(oracle_script), f"Oracle script {oracle_script} is missing."

    random.seed(42)
    charset = string.ascii_letters + string.digits

    for i in range(100):
        length = random.randint(4, 64)
        test_input = ''.join(random.choice(charset) for _ in range(length))

        try:
            expected_output = oracle_token(test_input)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle script failed on input '{test_input}': {e.stderr}")

        agent_res = subprocess.run(
            ['python3', agent_script, test_input],
            capture_output=True,
            text=True,
        )
        assert agent_res.returncode == 0, (
            f"Agent script failed (exit code {agent_res.returncode}) on input "
            f"'{test_input}'. Stderr: {agent_res.stderr}"
        )

        actual_output = agent_res.stdout.strip()
        assert actual_output == expected_output, (
            f"Fuzzing mismatch on iteration {i + 1}!\n"
            f"Input Username: '{test_input}'\n"
            f"Expected Token: '{expected_output}'\n"
            f"Actual Token:   '{actual_output}'"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
