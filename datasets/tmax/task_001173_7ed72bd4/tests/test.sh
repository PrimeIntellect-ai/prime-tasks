#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import random
import re
import socket
import subprocess
import time
import urllib.error
import urllib.request
import uuid


def test_files_exist():
    assert os.path.isdir('/home/user/workspace'), '/home/user/workspace directory is missing.'
    assert os.path.isdir('/home/user/venv'), '/home/user/venv directory is missing.'
    expected_files = [
        '/home/user/workspace/requirements.txt',
        '/home/user/workspace/dag.py',
        '/home/user/workspace/app.py',
        '/home/user/workspace/test_app.py',
        '/home/user/start_server.sh',
    ]
    for path in expected_files:
        assert os.path.isfile(path), f'File {path} is missing.'


def test_agent_tests_pass_and_are_present():
    cmd = 'source /home/user/venv/bin/activate && pytest /home/user/workspace/test_app.py'
    result = subprocess.run(cmd, shell=True, executable='/bin/bash', capture_output=True, text=True)
    assert result.returncode == 0, f'Agent tests failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'

    collect = subprocess.run(
        'source /home/user/venv/bin/activate && pytest --collect-only -q /home/user/workspace/test_app.py',
        shell=True,
        executable='/bin/bash',
        capture_output=True,
        text=True,
    )
    assert collect.returncode == 0, f'Could not collect agent tests:\n{collect.stdout}\n{collect.stderr}'
    match = re.search(r'(\d+) tests? collected', collect.stdout + collect.stderr)
    assert match and int(match.group(1)) >= 3, 'test_app.py must contain a nonempty suite covering the required areas.'

    source = open('/home/user/workspace/test_app.py', encoding='utf-8').read()
    tree = ast.parse(source)
    tests = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name.startswith('test_')]
    fixtures = []
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for decorator in node.decorator_list:
                name = ast.unparse(decorator).lower()
                if 'fixture' in name:
                    fixtures.append(node)
    lowered = source.lower()
    assert len(tests) >= 3, 'test_app.py must define tests for topology, cycles, and rate limiting.'
    assert fixtures, 'test_app.py must define a pytest fixture.'
    assert 'artifactdag' in lowered and 'build_order' in lowered, 'Tests must exercise ArtifactDAG topological ordering.'
    assert 'cyclicdependencyerror' in lowered, 'Tests must exercise CyclicDependencyError.'
    assert 'rate' in lowered and ('mock' in lowered or 'monkeypatch' in lowered), 'Tests must mock rate-limiting behavior.'


def load_dag_module():
    path = '/home/user/workspace/dag.py'
    spec = importlib.util.spec_from_file_location('submission_dag_' + uuid.uuid4().hex, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def assert_valid_order(order, expected, dependencies):
    assert isinstance(order, list), f'Build order must be a list, got {type(order)}'
    assert len(order) == len(set(order)), f'Build order contains duplicates: {order}'
    assert set(order) == set(expected), f'Expected exactly {set(expected)}, got {set(order)}'
    positions = {item: i for i, item in enumerate(order)}
    for artifact, deps in dependencies.items():
        for dep in deps:
            assert positions[dep] < positions[artifact], f'{dep} must precede {artifact}: {order}'


def test_artifact_dag_general_behavior():
    module = load_dag_module()
    assert hasattr(module, 'ArtifactDAG'), 'dag.py does not define ArtifactDAG.'
    assert hasattr(module, 'CyclicDependencyError'), 'dag.py does not define CyclicDependencyError.'
    assert issubclass(module.CyclicDependencyError, Exception)

    tag = uuid.uuid4().hex[:10]
    keys = [f'{tag}_n{i}@{1 + i % 3}.{i}.0' for i in range(9)]
    dependencies = {
        keys[0]: [],
        keys[1]: [],
        keys[2]: [keys[0]],
        keys[3]: [keys[0], keys[1]],
        keys[4]: [keys[2]],
        keys[5]: [keys[2], keys[3]],
        keys[6]: [keys[1]],
        keys[7]: [keys[4], keys[6]],
        keys[8]: [keys[5], keys[7]],
    }
    dag = module.ArtifactDAG()
    insertion = list(keys)
    random.SystemRandom().shuffle(insertion)
    # Definitions may reference artifacts that are added later, as required by cycle detection.
    for key in insertion:
        name, version = key.rsplit('@', 1)
        dag.add_artifact(name, version, list(dependencies[key]))

    root_name, root_version = keys[8].rsplit('@', 1)
    order = dag.get_build_order(root_name, root_version)
    assert_valid_order(order, keys, dependencies)

    shared_name = f'{tag}_versioned'
    dag.add_artifact(shared_name, '1.2.3', [])
    dag.add_artifact(shared_name, '2.4.6', [f'{shared_name}@1.2.3'])
    assert dag.get_build_order(shared_name, '2.4.6') == [f'{shared_name}@1.2.3', f'{shared_name}@2.4.6']

    missing = module.ArtifactDAG()
    a, b, c = (f'{tag}_cycle_{x}' for x in 'abc')
    missing.add_artifact(a, '7.1', [f'{b}@7.1'])
    missing.add_artifact(b, '7.1', [f'{c}@7.1'])
    try:
        missing.add_artifact(c, '7.1', [f'{a}@7.1'])
    except module.CyclicDependencyError:
        pass
    else:
        raise AssertionError('A generated three-node cycle did not raise CyclicDependencyError.')


def wait_for_port(port, timeout=10):
    start = time.time()
    while time.time() - start < timeout:
        try:
            with socket.create_connection(('localhost', port), timeout=1):
                return True
        except OSError:
            time.sleep(0.25)
    return False


def kill_port_8080():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table, encoding='ascii') as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(':', 1)[-1].upper() == '1F90' and fields[3] == '0A':
                        inodes.add(fields[9])
        except OSError:
            pass
    pids = set()
    for entry in os.listdir('/proc'):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(entry))
        except OSError:
            continue
    for pid in pids:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and wait_for_port(8080, timeout=0.1):
        time.sleep(0.1)
    for pid in pids:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass


def start_server():
    kill_port_8080()
    os.chmod('/home/user/start_server.sh', 0o755)
    result = subprocess.run(['/home/user/start_server.sh'], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f'start_server.sh failed:\n{result.stdout}\n{result.stderr}'
    assert wait_for_port(8080), 'Server did not bind to port 8080 within the timeout.'


def post_artifact(name, version, deps):
    data = json.dumps({'name': name, 'version': version, 'deps': deps}).encode()
    request = urllib.request.Request(
        'http://localhost:8080/artifacts', data=data, headers={'Content-Type': 'application/json'}
    )
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def get_resolve(name, version):
    request = urllib.request.Request(f'http://localhost:8080/resolve/{name}/{version}')
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            return response.status, json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def test_api_generated_graph_and_missing_artifact():
    start_server()
    try:
        tag = uuid.uuid4().hex[:12]
        keys = [f'{tag}x{i}@{i + 2}.0.{i}' for i in range(6)]
        deps = {
            keys[0]: [],
            keys[1]: [],
            keys[2]: [keys[0]],
            keys[3]: [keys[0], keys[1]],
            keys[4]: [keys[2], keys[3]],
            keys[5]: [keys[1], keys[4]],
        }
        for key in keys:
            name, version = key.rsplit('@', 1)
            status, _ = post_artifact(name, version, deps[key])
            assert status == 201, f'Expected 201 while adding generated artifact {key}, got {status}'

        name, version = keys[-1].rsplit('@', 1)
        status, body = get_resolve(name, version)
        assert status == 200, f'Expected 200 resolving generated graph, got {status}'
        assert isinstance(body, dict) and 'build_order' in body
        assert_valid_order(body['build_order'], keys, deps)

        status, _ = get_resolve(f'{tag}_absent', '99.88.77')
        assert status == 404, f'Expected 404 for an unknown artifact, got {status}'

        ca, cb = f'{tag}_ca', f'{tag}_cb'
        status, _ = post_artifact(ca, '3.7', [f'{cb}@3.7'])
        assert status == 201
        status, _ = post_artifact(cb, '3.7', [f'{ca}@3.7'])
        assert status == 400, f'Expected 400 for generated cycle, got {status}'
    finally:
        kill_port_8080()


def test_original_api_behavior_and_exact_rate_limit():
    start_server()
    try:
        status, _ = post_artifact('base', '1.0', [])
        assert status == 201, f'Expected 201 for base artifact, got {status}'
        status, _ = post_artifact('mid', '1.0', ['base@1.0'])
        assert status == 201, f'Expected 201 for mid artifact, got {status}'
        status, _ = post_artifact('top', '1.0', ['mid@1.0'])
        assert status == 201, f'Expected 201 for top artifact, got {status}'

        status, data = get_resolve('top', '1.0')
        assert status == 200, f'Expected 200 for resolve, got {status}'
        assert 'build_order' in data, "Response missing 'build_order' key"
        expected_order = ['base@1.0', 'mid@1.0', 'top@1.0']
        assert data['build_order'] == expected_order, f"Expected build order {expected_order}, got {data['build_order']}"

        status, _ = post_artifact('cycleA', '1.0', ['cycleB@1.0'])
        assert status == 201, f'Expected 201 for cycleA artifact, got {status}'
        status, _ = post_artifact('cycleB', '1.0', ['cycleA@1.0'])
        assert status == 400, f'Expected 400 for cyclic dependency, got {status}'

        rate_limited = False
        for i in range(10):
            status, _ = post_artifact(f'spam{i}', '1.0', [])
            if i < 5:
                assert status == 201, f'Request {i + 6} should be allowed under a 10/minute limit, got {status}'
            elif i == 5:
                assert status == 429, f'The 11th POST request must return 429, got {status}'
            if status == 429:
                rate_limited = True
                break
        assert rate_limited, 'Rate limiting (429) was not triggered after exceeding 10 requests per minute.'
    finally:
        kill_port_8080()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
