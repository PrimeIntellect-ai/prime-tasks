#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import urllib.request

import yaml

COMPOSE_FILE = '/app/docker-compose.yml'


def compose_command():
    candidates = [['docker', 'compose'], ['docker-compose']]
    for command in candidates:
        result = subprocess.run(command + ['version'], capture_output=True, text=True)
        if result.returncode == 0:
            return command
    raise AssertionError('Neither docker compose nor docker-compose is available')


def compose_container_id(service):
    command = compose_command() + ['-f', COMPOSE_FILE, 'ps', '-q', service]
    result = subprocess.run(command, cwd='/app', capture_output=True, text=True)
    assert result.returncode == 0, f"Compose could not inspect {service}: {result.stderr}"
    ids = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert len(ids) == 1, f"Expected one running Compose container for {service}, got: {ids}"
    return ids[0]


def inspect_container(container_id):
    result = subprocess.run(['docker', 'inspect', container_id], capture_output=True, text=True)
    assert result.returncode == 0, f"Could not inspect container {container_id}: {result.stderr}"
    return json.loads(result.stdout)[0]


def test_symlink_created():
    symlink_path = '/home/user/www'
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink"
    target = os.readlink(symlink_path)
    assert target == '/app/static' or os.path.abspath(os.path.join(os.path.dirname(symlink_path), target)) == '/app/static', \
        f"{symlink_path} does not point to /app/static"


def test_compose_file_exposes_nginx_port():
    assert os.path.isfile(COMPOSE_FILE), f"{COMPOSE_FILE} is missing"
    with open(COMPOSE_FILE, 'r') as handle:
        config = yaml.safe_load(handle)

    assert isinstance(config, dict), 'docker-compose.yml is not a valid Compose mapping'
    services = config.get('services')
    assert isinstance(services, dict), 'docker-compose.yml has no services mapping'
    assert 'proxy' in services, 'docker-compose.yml has no proxy service'

    proxy = services['proxy']
    assert isinstance(proxy, dict), 'proxy service configuration is invalid'
    ports = proxy.get('ports', [])
    assert isinstance(ports, list), 'proxy ports must be a list'

    mapping_found = False
    for port in ports:
        if isinstance(port, dict):
            try:
                mapping_found |= int(port.get('published')) == 8080 and int(port.get('target')) == 80
            except (TypeError, ValueError):
                pass
        else:
            value = str(port).split('/', 1)[0]
            pieces = value.rsplit(':', 2)
            if len(pieces) >= 2:
                try:
                    mapping_found |= int(pieces[-2]) == 8080 and int(pieces[-1]) == 80
                except ValueError:
                    pass

    assert mapping_found, 'proxy service does not declare host port 8080 mapped to container port 80'


def test_compose_services_are_running():
    proxy_id = compose_container_id('proxy')
    backend_id = compose_container_id('backend')

    proxy = inspect_container(proxy_id)
    backend = inspect_container(backend_id)
    assert proxy['State']['Running'], 'Compose proxy container is not running'
    assert backend['State']['Running'], 'Compose backend container is not running'

    labels = proxy.get('Config', {}).get('Labels') or {}
    assert labels.get('com.docker.compose.service') == 'proxy', 'Proxy was not started as the Compose proxy service'

    image = proxy.get('Config', {}).get('Image', '')
    image_name = image.rsplit('/', 1)[-1]
    assert image_name == 'nginx' or image_name.startswith('nginx:'), f'Proxy is not using an Nginx image: {image}'

    bindings = proxy.get('HostConfig', {}).get('PortBindings') or {}
    host_bindings = bindings.get('80/tcp') or []
    assert any(str(binding.get('HostPort')) == '8080' for binding in host_bindings), \
        'Running proxy container does not publish host port 8080 to container port 80'

    nginx_test = subprocess.run(['docker', 'exec', proxy_id, 'nginx', '-t'], capture_output=True, text=True)
    assert nginx_test.returncode == 0, f'Nginx configuration test failed: {nginx_test.stderr}'


def test_nginx_serving_static():
    static_file_path = '/app/static/index.html'
    assert os.path.exists(static_file_path), f"{static_file_path} is missing"
    with open(static_file_path, 'r') as f:
        expected_content = f.read().strip()

    try:
        response = urllib.request.urlopen('http://localhost:8080/index.html', timeout=5)
        actual_content = response.read().decode('utf-8').strip()
        server_header = response.headers.get('Server', '')
    except Exception as e:
        assert False, f"Failed to fetch http://localhost:8080/index.html: {e}"

    assert actual_content == expected_content, 'Content served by Nginx does not match the static file'
    assert server_header.lower().startswith('nginx'), f'Port 8080 is not reporting an Nginx server: {server_header}'


def test_fuzz_equivalence_process_log():
    agent_script = '/home/user/process_log.py'
    oracle_script = '/tests/oracle_process_log.py'

    assert os.path.isfile(agent_script), f"{agent_script} does not exist or is not a file"
    assert os.path.isfile(oracle_script), f"Verification oracle {oracle_script} does not exist"

    with open(agent_script, 'rb') as agent_file, open(oracle_script, 'rb') as oracle_file:
        assert agent_file.read() != oracle_file.read(), 'Agent script is byte-identical to the reference implementation'

    random.seed(42)
    methods = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS']
    paths = ['/api/data', '/login', '/index.html', '/images/logo.png', '/about', '/']

    for _ in range(100):
        ip = f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 255)}"
        method = random.choice(methods)
        path = random.choice(paths)
        status = random.randint(200, 599)
        size = random.randint(0, 10000)
        day = random.randint(1, 28)

        log_line = f'{ip} - - [{day:02d}/Oct/2023:14:00:00 -0700] "{method} {path} HTTP/1.1" {status} {size}'

        agent_result = subprocess.run(['python3', agent_script, log_line], capture_output=True, text=True)
        oracle_result = subprocess.run(['python3', oracle_script, log_line], capture_output=True, text=True)

        assert agent_result.returncode == 0, f"Agent script failed on input: {log_line}\nStderr: {agent_result.stderr}"

        agent_output = agent_result.stdout.strip()
        oracle_output = oracle_result.stdout.strip()

        assert agent_output == oracle_output, \
            f"Output mismatch for input: {log_line}\nExpected (Oracle): {oracle_output}\nGot (Agent): {agent_output}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
