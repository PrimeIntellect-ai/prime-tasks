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
from pathlib import Path

ORGANIZER = Path('/home/user/organizer')
MANIFEST = Path('/home/user/manifest.json')


def get_manifest():
    with open(MANIFEST, 'r') as f:
        return json.load(f)


def run_organizer(clean=False):
    assert ORGANIZER.is_dir(), '/home/user/organizer/ does not exist.'
    cargo_toml = ORGANIZER / 'Cargo.toml'
    assert cargo_toml.is_file(), '/home/user/organizer/Cargo.toml does not exist.'

    rust_sources = [p for p in ORGANIZER.rglob('*.rs') if p.is_file()]
    assert rust_sources, 'No Rust source files were found in /home/user/organizer/.'
    assert any(re.search(r'\bfn\s+main\s*\(', p.read_text(errors='ignore')) for p in rust_sources), \
        'The organizer has no Rust main function.'

    env = os.environ.copy()
    env['HOME'] = '/home/user'
    if Path('/home/user/.cargo').is_dir():
        env['CARGO_HOME'] = '/home/user/.cargo'

    if clean:
        result = subprocess.run(
            ['/usr/bin/cargo', 'clean', '--manifest-path', str(cargo_toml)],
            cwd=str(ORGANIZER), env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
        )
        assert result.returncode == 0, f'cargo clean failed:\n{result.stdout}'

    result = subprocess.run(
        ['/usr/bin/cargo', 'run', '--quiet', '--manifest-path', str(cargo_toml)],
        cwd=str(ORGANIZER), env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240
    )
    assert result.returncode == 0, f'The Rust organizer failed to compile or run:\n{result.stdout}'


def test_00_compile_and_run_rust_organizer():
    run_organizer(clean=True)


def test_build_order_txt():
    build_order_path = '/home/user/build_order.txt'
    assert os.path.isfile(build_order_path), f'{build_order_path} does not exist.'

    with open(build_order_path, 'r') as f:
        content = f.read().strip()

    order = [x.strip() for x in content.split(',') if x.strip()]

    expected_orders = [
        ['db-migration', 'auth-service', 'user-service', 'api-gateway', 'frontend'],
        ['db-migration', 'user-service', 'auth-service', 'api-gateway', 'frontend']
    ]

    assert order in expected_orders, f'Invalid topological sort in build_order.txt: {order}'


def test_build_all_sh():
    build_all_path = '/home/user/build_all.sh'
    assert os.path.isfile(build_all_path), f'{build_all_path} does not exist.'

    with open(build_all_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_commands = {
        'db-migration': 'bash db-migration.sh',
        'auth-service': 'cargo build --release --bin auth-service',
        'user-service': 'cargo build --release --bin user-service',
        'api-gateway': 'cargo build --release --bin api-gateway',
        'frontend': 'npm install && npm run build --prefix frontend'
    }

    expected_file_1 = [
        expected_commands['db-migration'],
        expected_commands['auth-service'],
        expected_commands['user-service'],
        expected_commands['api-gateway'],
        expected_commands['frontend']
    ]

    expected_file_2 = [
        expected_commands['db-migration'],
        expected_commands['user-service'],
        expected_commands['auth-service'],
        expected_commands['api-gateway'],
        expected_commands['frontend']
    ]

    assert lines in [expected_file_1, expected_file_2], f'Invalid commands or order in build_all.sh: {lines}'


def test_nginx_conf():
    nginx_conf_path = '/home/user/nginx.conf'
    assert os.path.isfile(nginx_conf_path), f'{nginx_conf_path} does not exist.'

    with open(nginx_conf_path, 'r') as f:
        content = f.read()

    assert 'events' in content, "nginx.conf missing 'events' block."
    assert 'http' in content, "nginx.conf missing 'http' block."
    assert 'server' in content, "nginx.conf missing 'server' block."
    assert 'listen 8080;' in content, "nginx.conf missing 'listen 8080;'."

    locations = re.findall(r'location\s+([^\s]+)\s*\{\s*proxy_pass\s+http://127\.0\.0\.1:(\d+);\s*\}', content)

    expected_locations = [
        ('/', '3000'),
        ('/api', '8082'),
        ('/auth', '8081'),
        ('/users', '8083')
    ]

    assert locations == expected_locations, f'Locations in nginx.conf are missing, incorrect, or not sorted alphabetically by route. Found: {locations}'


def test_program_handles_unseen_manifest():
    original_manifest = MANIFEST.read_bytes()
    suffix = secrets.token_hex(5)
    base_port = 12000 + secrets.randbelow(20000)

    services = [
        {'name': f'prep-{suffix}', 'lang': 'bash', 'port': None, 'deps': [], 'route': None},
        {'name': f'assets-{suffix}', 'lang': 'node', 'port': base_port, 'deps': [f'prep-{suffix}'], 'route': f'/assets-{suffix}'},
        {'name': f'identity-{suffix}', 'lang': 'rust', 'port': base_port + 1, 'deps': [f'prep-{suffix}'], 'route': f'/identity-{suffix}'},
        {'name': f'worker-{suffix}', 'lang': 'bash', 'port': None, 'deps': [f'prep-{suffix}'], 'route': None},
        {'name': f'gateway-{suffix}', 'lang': 'rust', 'port': base_port + 2, 'deps': [f'identity-{suffix}', f'assets-{suffix}'], 'route': '/'},
        {'name': f'reports-{suffix}', 'lang': 'node', 'port': base_port + 3, 'deps': [f'gateway-{suffix}', f'worker-{suffix}'], 'route': f'/reports-{suffix}'}
    ]
    random.SystemRandom().shuffle(services)

    try:
        MANIFEST.write_text(json.dumps({'services': services}, indent=2) + '\n')
        run_organizer(clean=False)

        order_path = Path('/home/user/build_order.txt')
        assert order_path.is_file(), 'Dynamic run did not create build_order.txt.'
        order = [x.strip() for x in order_path.read_text().strip().split(',') if x.strip()]
        names = [service['name'] for service in services]
        assert len(order) == len(names), f'Wrong number of services in dynamic build order: {order}'
        assert set(order) == set(names), f'Dynamic build order has missing, duplicate, or unknown services: {order}'
        positions = {name: i for i, name in enumerate(order)}
        for service in services:
            for dep in service['deps']:
                assert positions[dep] < positions[service['name']], \
                    f'Dependency {dep} appears after {service["name"]} in dynamic build order.'

        commands = {
            service['name']: (
                f'cargo build --release --bin {service["name"]}' if service['lang'] == 'rust' else
                f'npm install && npm run build --prefix {service["name"]}' if service['lang'] == 'node' else
                f'bash {service["name"]}.sh'
            )
            for service in services
        }
        build_lines = [line.strip() for line in Path('/home/user/build_all.sh').read_text().splitlines() if line.strip()]
        expected_lines = [commands[name] for name in order]
        assert build_lines == expected_lines, f'Dynamic build_all.sh is incorrect: {build_lines}'

        nginx_content = Path('/home/user/nginx.conf').read_text()
        assert 'events' in nginx_content, "Dynamic nginx.conf missing 'events' block."
        assert 'http' in nginx_content, "Dynamic nginx.conf missing 'http' block."
        assert 'server' in nginx_content, "Dynamic nginx.conf missing 'server' block."
        assert 'listen 8080;' in nginx_content, "Dynamic nginx.conf missing 'listen 8080;'."
        locations = re.findall(r'location\s+([^\s]+)\s*\{\s*proxy_pass\s+http://127\.0\.0\.1:(\d+);\s*\}', nginx_content)
        expected_locations = sorted(
            [(service['route'], str(service['port'])) for service in services
             if service['route'] is not None and service['port'] is not None],
            key=lambda item: item[0]
        )
        assert locations == expected_locations, \
            f'Dynamic Nginx locations are incorrect or unsorted. Found: {locations}'
    finally:
        MANIFEST.write_bytes(original_manifest)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
