#!/bin/bash
set +e
mkdir -p /logs/verifier
reward=0

READELF_REAL=/usr/bin/readelf.verifier-real
LDD_REAL=/usr/bin/ldd.verifier-real

cleanup() {
    if [ -e "$READELF_REAL" ]; then
        rm -f /usr/bin/readelf
        mv "$READELF_REAL" /usr/bin/readelf
    fi
    if [ -e "$LDD_REAL" ]; then
        rm -f /usr/bin/ldd
        mv "$LDD_REAL" /usr/bin/ldd
    fi
    echo "$reward" > /logs/verifier/reward.txt
}
trap cleanup EXIT

rm -f /tmp/verifier-readelf.log /tmp/verifier-ldd.log /tmp/traversal_ok.json
mv /usr/bin/readelf "$READELF_REAL" || exit 1
mv /usr/bin/ldd "$LDD_REAL" || exit 1

cat > /usr/bin/readelf <<'EOF'
#!/bin/sh
echo "$@" >> /tmp/verifier-readelf.log
exec /usr/bin/readelf.verifier-real "$@"
EOF
chmod 755 /usr/bin/readelf

cat > /usr/bin/ldd <<'EOF'
#!/bin/sh
echo "$@" >> /tmp/verifier-ldd.log
exit 97
EOF
chmod 755 /usr/bin/ldd

cat > /tmp/check_traversal.py <<'PY'
import inspect
import json
import sys

sys.path.insert(0, '/home/user')
import server

graph = {
    'A': ['B', 'C'],
    'B': ['C', 'D'],
    'C': ['A'],
    'D': ['D'],
}
expected = {'A', 'B', 'C', 'D'}
accepted = []
keywords = ('travers', 'depend', 'collect', 'walk', 'search', 'dfs', 'bfs')

for name, fn in inspect.getmembers(server, inspect.isfunction):
    if not any(k in name.lower() for k in keywords):
        continue
    try:
        sig = inspect.signature(fn)
        positional = [p for p in sig.parameters.values()
                      if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]
        required = [p for p in positional if p.default is p.empty]
        if len(positional) < 2 or len(required) > 2:
            continue
    except Exception:
        continue

    resolver = lambda node: list(graph.get(node, []))
    for args in (('A', resolver), (resolver, 'A')):
        try:
            result = fn(*args)
            if isinstance(result, dict):
                values = list(result.keys())
            elif isinstance(result, (str, bytes)) or result is None:
                continue
            else:
                values = list(result)
            value_set = set(values)
            # Traversal helpers may include the starting node or return only dependencies.
            if value_set in (expected, expected - {'A'}) and len(values) == len(value_set):
                accepted.append(name)
                break
        except Exception:
            pass

accepted = sorted(set(accepted))
with open('/tmp/traversal_ok.json', 'w') as f:
    json.dump(accepted, f)
if not accepted:
    raise SystemExit('No abstract traversal function correctly handled a cyclic graph')
PY

cat > /tmp/test_final_state.py <<'PY'
import ast
import json
import os
import re
import stat
import subprocess
import sys
import tarfile
import time

import grpc
import pytest

HOME = '/home/user'
SEARCH_DIRS = [
    '/lib/x86_64-linux-gnu',
    '/usr/lib/x86_64-linux-gnu',
    '/lib',
    '/usr/lib',
]
REAL_READELF = '/usr/bin/readelf.verifier-real'
NEEDED_RE = re.compile(r'\(NEEDED\).*?\[([^]]+)\]')


def direct_needed(path):
    out = subprocess.check_output(
        [REAL_READELF, '-d', path], stderr=subprocess.STDOUT, text=True
    )
    return NEEDED_RE.findall(out)


def expected_dependencies(root):
    visited = {root}
    dependencies = set()
    pending = [root]
    while pending:
        current = pending.pop()
        for soname in direct_needed(current):
            resolved = None
            for directory in SEARCH_DIRS:
                candidate = os.path.join(directory, soname)
                if os.path.isfile(candidate):
                    resolved = os.path.abspath(candidate)
                    break
            if resolved is None:
                continue
            dependencies.add(resolved)
            if resolved not in visited:
                visited.add(resolved)
                pending.append(resolved)
    return dependencies


@pytest.fixture(scope='session')
def running_server():
    proc = subprocess.Popen(
        [sys.executable, '/home/user/server.py'],
        cwd='/home/user',
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=os.environ.copy(),
    )
    channel = grpc.insecure_channel('127.0.0.1:50051')
    try:
        grpc.channel_ready_future(channel).result(timeout=12)
    except Exception:
        proc.terminate()
        proc.wait(timeout=5)
        pytest.fail('server.py did not start a gRPC service on port 50051')
    yield channel, proc
    channel.close()
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


def test_protobuf_compiled_and_functional():
    assert os.path.isfile('/home/user/deps_pb2.py'), 'deps_pb2.py is missing'
    assert os.path.isfile('/home/user/deps_pb2_grpc.py'), 'deps_pb2_grpc.py is missing'
    sys.path.insert(0, '/home/user')
    import deps_pb2
    import deps_pb2_grpc

    request = deps_pb2.AnalyzeRequest(binary_path='/usr/bin/sqlite3')
    encoded = request.SerializeToString()
    assert deps_pb2.AnalyzeRequest.FromString(encoded).binary_path == '/usr/bin/sqlite3'
    service = deps_pb2.DESCRIPTOR.services_by_name.get('DependencyAnalyzer')
    assert service is not None
    assert service.full_name == 'deps.DependencyAnalyzer'
    assert [m.name for m in service.methods] == ['Analyze']
    assert hasattr(deps_pb2_grpc, 'DependencyAnalyzerStub')
    assert hasattr(deps_pb2_grpc, 'DependencyAnalyzerServicer')


def test_files_exist():
    for filename in ['server.py', 'client.py', 'test_server.py']:
        path = os.path.join('/home/user', filename)
        assert os.path.isfile(path), f'{filename} is missing at {path}'


def test_abstract_traversal_handles_cycles():
    try:
        subprocess.run(
            [sys.executable, '/tmp/check_traversal.py'],
            check=True,
            timeout=8,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        pytest.fail(f'No usable resolver-injected traversal implementation: {e}')


def test_submitted_hypothesis_test_is_connected_to_traversal():
    test_path = '/home/user/test_server.py'
    assert os.path.isfile(test_path), f'{test_path} is missing'
    source = open(test_path, encoding='utf-8').read()
    tree = ast.parse(source, filename=test_path)
    accepted = set(json.load(open('/tmp/traversal_ok.json')))

    given_aliases = {'given'}
    server_module_aliases = {'server'}
    imported_server_names = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            if node.module == 'hypothesis':
                for item in node.names:
                    if item.name == 'given':
                        given_aliases.add(item.asname or item.name)
            if node.module == 'server':
                for item in node.names:
                    imported_server_names[item.asname or item.name] = item.name
        elif isinstance(node, ast.Import):
            for item in node.names:
                if item.name == 'server':
                    server_module_aliases.add(item.asname or item.name)

    def tail_name(expr):
        if isinstance(expr, ast.Name):
            return expr.id
        if isinstance(expr, ast.Attribute):
            return expr.attr
        return None

    meaningful = False
    for fn in [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]:
        decorated = any(
            isinstance(d, ast.Call) and tail_name(d.func) in given_aliases
            for d in fn.decorator_list
        )
        if not decorated or not any(isinstance(n, ast.Assert) for n in ast.walk(fn)):
            continue
        called = set()
        for call in [n for n in ast.walk(fn) if isinstance(n, ast.Call)]:
            if isinstance(call.func, ast.Name):
                called.add(imported_server_names.get(call.func.id, call.func.id))
            elif (isinstance(call.func, ast.Attribute)
                  and isinstance(call.func.value, ast.Name)
                  and call.func.value.id in server_module_aliases):
                called.add(call.func.attr)
        if called & accepted:
            meaningful = True
            break

    strategy_names = {
        tail_name(n.func) for n in ast.walk(tree) if isinstance(n, ast.Call)
    }
    strategy_names.update(
        tail_name(n) for n in ast.walk(tree) if isinstance(n, ast.Attribute)
    )
    graph_strategy_markers = {
        'dictionaries', 'recursive', 'composite', 'builds', 'lists', 'sets', 'tuples'
    }
    assert strategy_names & graph_strategy_markers, 'Hypothesis test does not define a graph-generating strategy'
    assert meaningful, 'A @given test must call and assert on the actual traversal function'

    try:
        subprocess.run(
            ['pytest', test_path], check=True, timeout=30,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            cwd='/home/user',
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        pytest.fail(f'Hypothesis tests failed or timed out: {e}')


def test_grpc_analyzer_and_client(running_server):
    channel, proc = running_server
    sys.path.insert(0, '/home/user')
    import deps_pb2
    import deps_pb2_grpc
    stub = deps_pb2_grpc.DependencyAnalyzerStub(channel)

    for binary in ('/usr/bin/sqlite3', '/usr/bin/python3'):
        expected = expected_dependencies(binary)
        response = stub.Analyze(
            deps_pb2.AnalyzeRequest(binary_path=binary), timeout=15
        )
        actual = list(response.shared_libraries)
        assert len(actual) == len(set(actual)), f'Analyze returned duplicate paths for {binary}'
        assert all(os.path.isabs(p) for p in actual), 'Analyze must return absolute paths'
        assert set(actual) == expected, f'Incorrect recursive dependency closure for {binary}'

    assert os.path.isfile('/tmp/verifier-readelf.log'), 'Analyze did not execute readelf'
    assert os.path.getsize('/tmp/verifier-readelf.log') > 0, 'Analyze did not execute readelf'
    assert not os.path.exists('/tmp/verifier-ldd.log') or os.path.getsize('/tmp/verifier-ldd.log') == 0, 'The implementation invoked forbidden ldd'

    result = subprocess.run(
        [sys.executable, '/home/user/client.py'],
        cwd='/home/user', env=os.environ.copy(), timeout=20,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    assert result.returncode == 0, f'client.py failed:\n{result.stdout}\n{result.stderr}'
    assert proc.poll() is None, 'server exited while serving the client'


def test_bundle_list():
    bundle_path = '/home/user/bundle_list.txt'
    assert os.path.isfile(bundle_path), f'bundle_list.txt is missing at {bundle_path}'
    with open(bundle_path, encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert '/usr/bin/sqlite3' in lines, 'Missing main binary (/usr/bin/sqlite3) in bundle_list.txt'
    assert any('libc.so' in p for p in lines), 'Missing libc dependency in bundle_list.txt'
    assert any('libm.so' in p for p in lines), 'Missing libm dependency in bundle_list.txt'
    assert lines == sorted(lines), 'bundle_list.txt is not sorted alphabetically'
    assert len(lines) == len(set(lines)), 'bundle_list.txt contains duplicates'
    assert all(os.path.isabs(p) and os.path.isfile(p) for p in lines), 'Bundle entries must be existing absolute files'

    expected = expected_dependencies('/usr/bin/sqlite3') | {'/usr/bin/sqlite3'}
    assert set(lines) == expected, 'bundle_list.txt is not the exact sqlite3 dependency closure'


def test_tar_contents():
    tar_path = '/home/user/minimal_sqlite3.tar'
    bundle_path = '/home/user/bundle_list.txt'
    assert os.path.isfile(tar_path), f'Tar archive is missing at {tar_path}'
    assert os.path.isfile(bundle_path), f'bundle_list.txt is missing at {bundle_path}'

    with open(bundle_path, encoding='utf-8') as f:
        expected_paths = [line.strip() for line in f if line.strip()]
    normalized_expected = ['/' + p.lstrip('/') for p in expected_paths]

    try:
        tar = tarfile.open(tar_path, 'r:')
    except tarfile.TarError as e:
        pytest.fail(f'{tar_path} is not a valid uncompressed tar: {e}')

    with tar:
        members = tar.getmembers()
        normalized_members = ['/' + m.name.lstrip('/') for m in members]
        assert '/usr/bin/sqlite3' in normalized_members, 'Tar archive missing sqlite3'
        assert len(normalized_members) == len(set(normalized_members)), 'Tar contains duplicate entries'
        assert set(normalized_members) == set(normalized_expected), 'Tar must contain exactly bundle_list.txt entries'

        by_path = {'/' + m.name.lstrip('/'): m for m in members}
        for path in normalized_expected:
            member = by_path[path]
            st = os.lstat(path)
            if stat.S_ISLNK(st.st_mode):
                assert member.issym(), f'{path} should be archived as a symbolic link'
                assert member.linkname == os.readlink(path), f'Wrong symlink target for {path}'
            else:
                assert member.isfile(), f'{path} should be a regular file in the tar'
                archived = tar.extractfile(member)
                assert archived is not None
                with open(path, 'rb') as original:
                    assert archived.read() == original.read(), f'Archived bytes differ for {path}'
PY

python3 -m pytest /tmp/test_final_state.py -x --tb=short
if [ $? -eq 0 ]; then
    reward=1
fi
exit 0
