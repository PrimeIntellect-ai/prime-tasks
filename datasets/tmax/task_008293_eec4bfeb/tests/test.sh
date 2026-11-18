#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

BASE = Path('/home/user/qa_env')
ROUTES = BASE / 'routes.json'
LOG = BASE / 'test_results.log'
BINARY = BASE / 'rust_router/target/debug/router_cli'

ORIGINAL_ROUTES = [
    {'pattern': '/users/:id', 'path': '/users/123'},
    {'pattern': '/api/v1/:resource/:action', 'path': '/api/v1/posts/delete'},
    {'pattern': '/static/:file', 'path': '/api/v1/posts/delete'},
]


def run_make(routes):
    cargo = shutil.which('cargo')
    python3 = shutil.which('python3')
    assert cargo, 'cargo is unavailable'
    assert python3, 'python3 is unavailable'

    ROUTES.write_text(json.dumps(routes, indent=2) + '\n')
    subprocess.run([cargo, 'clean'], cwd=BASE / 'rust_router', check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    BINARY.unlink(missing_ok=True)
    LOG.unlink(missing_ok=True)

    with tempfile.TemporaryDirectory(prefix='verifier-tools-') as td:
        tools = Path(td)
        cargo_marker = tools / 'cargo.called'
        python_marker = tools / 'python.called'

        (tools / 'cargo').write_text(
            '#!/bin/sh\n: > ' + shlex.quote(str(cargo_marker)) + '\nexec ' +
            shlex.quote(cargo) + ' "$@"\n'
        )
        (tools / 'python3').write_text(
            '#!/bin/sh\n'
            'case "$1" in\n'
            '  *test_env/test_runner.py) : > ' + shlex.quote(str(python_marker)) + ' ;;\n'
            'esac\n'
            'exec ' + shlex.quote(python3) + ' "$@"\n'
        )
        os.chmod(tools / 'cargo', 0o755)
        os.chmod(tools / 'python3', 0o755)

        env = os.environ.copy()
        env['PATH'] = str(tools) + os.pathsep + env.get('PATH', '')
        result = subprocess.run(
            ['make', '-C', str(BASE)], env=env, capture_output=True,
            text=True, timeout=180
        )
        assert result.returncode == 0, (
            'Default Makefile target failed.\nSTDOUT:\n' + result.stdout +
            '\nSTDERR:\n' + result.stderr
        )
        assert cargo_marker.exists(), 'The default Makefile target did not invoke cargo build'
        assert python_marker.exists(), 'The default Makefile target did not run test_env/test_runner.py with python3'

    assert BINARY.is_file(), 'The Makefile did not produce the Rust router binary'
    assert os.access(BINARY, os.X_OK), 'The produced Rust router binary is not executable'
    assert LOG.is_file(), 'The Makefile did not generate test_results.log'


@pytest.fixture(scope='session', autouse=True)
def build_and_run_original_project():
    old_routes = ROUTES.read_bytes() if ROUTES.exists() else None
    try:
        run_make(ORIGINAL_ROUTES)
        yield
    finally:
        if old_routes is None:
            ROUTES.unlink(missing_ok=True)
        else:
            ROUTES.write_bytes(old_routes)


def test_makefile_exists():
    makefile_path = "/home/user/qa_env/Makefile"
    assert os.path.isfile(makefile_path), "Makefile is missing at /home/user/qa_env/Makefile"

    with open(makefile_path, 'r') as f:
        content = f.read()

    assert "all:" in content, "Makefile must have a default 'all' target"


def test_test_runner_patched():
    runner_path = "/home/user/qa_env/test_env/test_runner.py"
    assert os.path.isfile(runner_path), f"File {runner_path} is missing"

    with open(runner_path, 'r') as f:
        content = f.read()

    assert "subprocess.run" in content, "test_runner.py does not appear to be patched. Missing subprocess.run logic."
    assert "routes.json" in content, "test_runner.py does not appear to be patched. Missing routes.json logic."


def test_results_log():
    log_path = "/home/user/qa_env/test_results.log"
    assert os.path.isfile(log_path), f"Log file is missing at {log_path}. Did the Makefile run successfully?"

    with open(log_path, 'r') as f:
        content = f.read().strip()

    expected = """/users/:id | /users/123 => id:123
/api/v1/:resource/:action | /api/v1/posts/delete => action:delete
resource:posts
/static/:file | /api/v1/posts/delete => NOMATCH"""

    assert content == expected, f"Contents of {log_path} do not match the expected output. Got:\n{content}"


def expected_router_output(pattern, path):
    pat_parts = pattern.split('/')
    path_parts = path.split('/')
    if len(pat_parts) != len(path_parts):
        return 'NOMATCH'

    params = {}
    for pat, value in zip(pat_parts, path_parts):
        if pat.startswith(':'):
            params[pat[1:]] = value
        elif pat != value:
            return 'NOMATCH'
    return '\n'.join(f'{key}:{params[key]}' for key in sorted(params))


def expected_log(routes):
    return ''.join(
        f"{route['pattern']} | {route['path']} => "
        f"{expected_router_output(route['pattern'], route['path'])}\n"
        for route in routes
    )


def test_router_harness_and_makefile_on_derived_inputs():
    token_a = uuid.uuid4().hex
    token_b = uuid.uuid4().hex
    token_c = uuid.uuid4().hex
    dynamic_routes = [
        {'pattern': '/tenant/:tenant/item/:id', 'path': f'/tenant/{token_a}/item/{token_b}'},
        {'pattern': '/download/:name/:version', 'path': f'/download/{token_c}/v9'},
        {'pattern': '/literal/:value/end', 'path': f'/literal/{token_b}/end'},
        {'pattern': '/fixed/:id', 'path': f'/wrong/{token_a}'},
        {'pattern': '/too/:short', 'path': f'/too/{token_c}/extra'},
    ]

    saved_routes = ROUTES.read_bytes() if ROUTES.exists() else None
    saved_log = LOG.read_bytes() if LOG.exists() else None
    try:
        run_make(dynamic_routes)
        assert LOG.read_text() == expected_log(dynamic_routes), (
            'The Makefile-generated log did not reflect the runtime-derived routes'
        )

        for route in dynamic_routes:
            result = subprocess.run(
                [str(BINARY), route['pattern'], route['path']],
                capture_output=True, text=True, timeout=10
            )
            assert result.returncode == 0, result.stderr
            assert result.stdout.strip() == expected_router_output(
                route['pattern'], route['path']
            )

        LOG.unlink(missing_ok=True)
        result = subprocess.run(
            [sys.executable, str(BASE / 'test_env/test_runner.py')],
            cwd=BASE, capture_output=True, text=True, timeout=60
        )
        assert result.returncode == 0, result.stderr
        assert LOG.is_file(), 'The patched Python harness did not create test_results.log'
        assert LOG.read_text() == expected_log(dynamic_routes), (
            'The patched Python harness did not execute the router for the supplied routes'
        )
    finally:
        if saved_routes is None:
            ROUTES.unlink(missing_ok=True)
        else:
            ROUTES.write_bytes(saved_routes)
        if saved_log is None:
            LOG.unlink(missing_ok=True)
        else:
            LOG.write_bytes(saved_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
