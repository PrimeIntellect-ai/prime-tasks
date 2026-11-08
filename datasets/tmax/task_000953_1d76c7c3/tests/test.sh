#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess
import urllib.error
import urllib.request

import pytest

PROJECT = '/home/user/api_project'
URL = 'http://127.0.0.1:8000/api/merge_sort'
EXPECTED_FIXED = [
    {"id": 1, "name": "Alpha"},
    {"id": 2, "name": "Bravo"},
    {"id": 3, "name": "Charlie"},
    {"id": 4, "name": "Delta"},
    {"id": 5, "name": "Echo"},
]


def post_json(payload):
    body = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(
        URL,
        data=body,
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            assert response.status == 200, f"Expected status code 200, got {response.status}"
            return json.loads(response.read().decode('utf-8'))
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to the Nginx proxy at {URL}. Are Nginx and the Python server running? Error: {e}")


def test_01_test_script_exists_runs_and_uses_proxy():
    test_path = os.path.join(PROJECT, 'test.py')
    result_path = os.path.join(PROJECT, 'result.json')
    access_path = os.path.join(PROJECT, 'logs', 'access.log')

    assert os.path.isfile(test_path), f"File {test_path} does not exist."

    old_size = os.path.getsize(access_path) if os.path.isfile(access_path) else 0
    if os.path.lexists(result_path):
        os.unlink(result_path)

    completed = subprocess.run(
        ['python3', test_path],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"Running {test_path} failed with exit code {completed.returncode}. "
        f"stdout: {completed.stdout!r}; stderr: {completed.stderr!r}"
    )
    assert os.path.isfile(result_path), f"File {result_path} does not exist. Did you run your test script?"

    assert os.path.isfile(access_path), "Nginx access log is missing after running test.py."
    new_size = os.path.getsize(access_path)
    with open(access_path, 'rb') as f:
        if new_size >= old_size:
            f.seek(old_size)
        new_log = f.read().decode('utf-8', errors='replace')
    assert re.search(r'"POST /api/merge_sort(?:\s|\?)', new_log), (
        "Running test.py did not make a POST request to /api/merge_sort through Nginx."
    )


def test_02_result_json():
    result_path = os.path.join(PROJECT, 'result.json')
    assert os.path.isfile(result_path), f"File {result_path} does not exist. Did you run your test script?"

    with open(result_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {result_path} does not contain valid JSON.")

    assert data == EXPECTED_FIXED, f"Content of {result_path} did not match the expected sorted list of objects."


def test_03_server_py_fixed():
    server_path = os.path.join(PROJECT, 'server.py')
    assert os.path.isfile(server_path), f"File {server_path} is missing."

    with open(server_path, 'r') as f:
        content = f.read()

    assert 'cmp=' not in content, "Python 2 'cmp=' sort idiom was not removed from server.py."
    assert 'iteritems()' not in content, "Python 2 'iteritems()' idiom was not removed from server.py."


def test_04_nginx_conf_fixed():
    nginx_path = os.path.join(PROJECT, 'nginx.conf')
    assert os.path.isfile(nginx_path), f"File {nginx_path} is missing."

    with open(nginx_path, 'r') as f:
        content = f.read()

    assert 'proxy_pass http://127.0.0.1:8080;' in content, "Nginx configuration does not proxy to the correct port (8080)."


def test_05_services_running_and_proxy_working():
    payload = {
        "list1": [{"id": 5, "name": "Echo"}, {"id": 1, "name": "Alpha"}, {"id": 3, "name": "Charlie"}],
        "list2": [{"id": 4, "name": "Delta"}, {"id": 2, "name": "Bravo"}],
    }
    resp_data = post_json(payload)
    assert resp_data == EXPECTED_FIXED, "The API did not return the correctly sorted list when accessed through the reverse proxy."


def test_06_merge_sort_generalizes_to_unseen_inputs():
    rng = random.SystemRandom()
    for trial in range(3):
        ids = rng.sample(range(-1000000, 1000001), 9)
        rng.shuffle(ids)
        objects = [
            {
                'id': value,
                'name': f"dynamic-{trial}-{secrets.token_hex(8)}",
                'marker': secrets.token_hex(6),
            }
            for value in ids
        ]
        split = rng.randint(1, len(objects) - 1)
        payload = {'list1': objects[:split], 'list2': objects[split:]}
        expected = sorted(payload['list1'] + payload['list2'], key=lambda item: item['id'])
        actual = post_json(payload)
        assert actual == expected, (
            f"The API did not genuinely merge and sort an unseen payload on trial {trial}."
        )

    assert post_json({'list1': [], 'list2': []}) == [], "The API did not correctly merge two empty lists."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
