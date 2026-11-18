#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import secrets
import subprocess
import sys
from pathlib import Path

import pytest
import requests
import urllib.parse

SERVICE_DIR = Path('/app/legacy_service')
MODULES = ('server', 'router', 'math_utils')


def compute_expected_hash(text: str) -> int:
    return sum(b * (i + 1) for i, b in enumerate(text.encode('utf-8'))) % 1000003


def make_random_cases():
    rng = secrets.SystemRandom()
    alphabet = list(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
        "!@#$%^&*()-_=+[]{};:'\",.<>/?\\|`~%&=#"
        "ëñçödîñg漢字かな한글Приветمرحبا"
        "🚀🌍😀🧪✨"
    )
    cases = []
    for _ in range(30):
        length = rng.randint(1, 300)
        # A random token makes every case unpredictable even if much of the
        # remaining text happens to repeat.
        prefix = secrets.token_hex(12)
        cases.append(prefix + ''.join(rng.choice(alphabet) for _ in range(length)))
    return cases


FIXED_CASES = [
    "hello",
    "test with spaces",
    "complex UTF-8: 🚀 ëñçödîñg",
    "a",
    "12345",
    "A very long string with multiple characters to test the modulo arithmetic correctly!"
]

RANDOM_CASES = make_random_cases()


def assert_endpoint(text):
    encoded_text = urllib.parse.quote(text)
    url = f"http://127.0.0.1:8080/compute?text={encoded_text}"

    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server or retrieve data at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP status code 200, got {response.status_code}. Response: {response.text}"

    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, f"Expected Content-Type to include 'application/json', got '{content_type}'"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON: {response.text}")

    assert "hash" in data, f"Response JSON does not contain the required 'hash' key. Got: {data}"

    expected_hash = compute_expected_hash(text)
    assert data["hash"] == expected_hash, f"For text '{text}', expected hash {expected_hash}, got {data['hash']}"


@pytest.mark.parametrize("text", FIXED_CASES)
def test_compute_endpoint(text):
    assert_endpoint(text)


@pytest.mark.parametrize("text", RANDOM_CASES)
def test_compute_endpoint_unpredictable_inputs(text):
    assert_endpoint(text)


def test_service_modules_are_python3_and_import_cleanly():
    for module in MODULES:
        path = SERVICE_DIR / f'{module}.py'
        assert path.is_file(), f'Missing required service module: {path}'
        source = path.read_text(encoding='utf-8')
        tree = ast.parse(source, filename=str(path))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imported = {alias.name.split('.')[0] for alias in node.names}
            elif isinstance(node, ast.ImportFrom) and node.module:
                imported = {node.module.split('.')[0]}
            else:
                continue
            assert not imported.intersection({'BaseHTTPServer', 'urlparse'}), \
                f'{path} still imports a Python 2-only standard library module'

    code = (
        "import sys; "
        "sys.path.insert(0, '/app/legacy_service'); "
        "import math_utils, router, server"
    )
    result = subprocess.run(
        [sys.executable, '-c', code],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, \
        f'Service modules do not import cleanly under Python 3: {result.stderr}'


def test_service_modules_have_no_circular_imports():
    dependencies = {module: set() for module in MODULES}
    for module in MODULES:
        path = SERVICE_DIR / f'{module}.py'
        tree = ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                names = {alias.name.split('.')[0] for alias in node.names}
            elif isinstance(node, ast.ImportFrom) and node.module:
                names = {node.module.split('.')[0]}
            else:
                continue
            dependencies[module].update(names.intersection(MODULES))

    visiting = set()
    visited = set()

    def visit(module):
        if module in visiting:
            return True
        if module in visited:
            return False
        visiting.add(module)
        if any(visit(dep) for dep in dependencies[module]):
            return True
        visiting.remove(module)
        visited.add(module)
        return False

    assert not any(visit(module) for module in MODULES), \
        f'Circular imports remain among service modules: {dependencies}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
