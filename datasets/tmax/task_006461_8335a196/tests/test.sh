#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import asyncio
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
import uuid

import pytest
import websockets

HOME = '/home/user'
ANALYZER = os.path.join(HOME, 'analyzer.py')
SERVER = os.path.join(HOME, 'server.py')
DUMP = os.path.join(HOME, 'ldd_dump.txt')


def load_analyzer():
    assert os.path.isfile(ANALYZER), f'{ANALYZER} does not exist or is not a file.'
    name = 'student_analyzer_' + uuid.uuid4().hex
    spec = importlib.util.spec_from_file_location(name, ANALYZER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, 'parse_ldd', None)), 'parse_ldd is missing or not callable.'
    assert callable(getattr(module, 'find_shortest_path', None)), 'find_shortest_path is missing or not callable.'
    return module


def oracle_bfs(graph, start, target):
    queue = [[start]]
    seen = {start}
    while queue:
        path = queue.pop(0)
        node = path[-1]
        if node == target:
            return path
        for child in graph.get(node, []):
            if child not in seen:
                seen.add(child)
                queue.append(path + [child])
    return []


def test_result_json():
    result_path = '/home/user/result.json'
    assert os.path.exists(result_path), f'{result_path} does not exist.'
    with open(result_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{result_path} does not contain valid JSON.')

    expected = ['libfront.so', 'libmiddle_b.so', 'libbase.so']
    assert data == expected, f'Expected {expected} in result.json, got {data}'


def test_analyzer_parser_and_shortest_path_on_fresh_inputs():
    analyzer = load_analyzer()
    tag = uuid.uuid4().hex
    root = f'libroot_{tag}.so'
    slow = f'libslow_{tag}.so'
    fast = f'libfast_{tag}.so'
    middle = f'libmiddle_{tag}.so'
    goal = f'libgoal_{tag}.so'
    isolated = f'libisolated_{tag}.so'

    dump_text = f'''[{root}]
    linux-vdso.so.1 =>  (0x1)
    {slow} => /tmp/{slow} (0x2)
    {fast} => /tmp/{fast} (0x3)
    libc.so.6 => /lib/libc.so.6 (0x4)
[{slow}]
    {middle} => /tmp/{middle} (0x5)
[{middle}]
    {goal} => /tmp/{goal} (0x6)
[{fast}]
    {goal} => /tmp/{goal} (0x7)
[{goal}]
    libc.so.6 => /lib/libc.so.6 (0x8)
[{isolated}]
'''
    with tempfile.NamedTemporaryFile('w', delete=False) as f:
        f.write(dump_text)
        path = f.name
    try:
        graph = analyzer.parse_ldd(path)
    finally:
        os.unlink(path)

    expected_graph = {
        root: [slow, fast],
        slow: [middle],
        middle: [goal],
        fast: [goal],
        goal: [],
        isolated: [],
    }
    assert graph == expected_graph
    assert analyzer.find_shortest_path(graph, root, goal) == [root, fast, goal]
    assert analyzer.find_shortest_path(graph, goal, root) == []
    assert analyzer.find_shortest_path(graph, isolated, goal) == []
    assert analyzer.find_shortest_path(graph, root, root) == [root]


def test_student_unittests():
    test_file = '/home/user/test_analyzer.py'
    assert os.path.exists(test_file), f'Unit test file {test_file} does not exist.'

    with open(test_file, 'r') as f:
        source = f.read()
    tree = ast.parse(source, filename=test_file)
    used_names = {node.id for node in ast.walk(tree) if isinstance(node, ast.Name)}
    used_attrs = {node.attr for node in ast.walk(tree) if isinstance(node, ast.Attribute)}
    assert 'mock_open' in used_names or 'mock_open' in used_attrs, 'Tests must use unittest.mock.mock_open.'

    count_script = '''
import importlib.util, unittest
p = "/home/user/test_analyzer.py"
s = importlib.util.spec_from_file_location("student_tests", p)
m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)
print(unittest.defaultTestLoader.loadTestsFromModule(m).countTestCases())
'''
    counted = subprocess.run([sys.executable, '-c', count_script], cwd=HOME, capture_output=True, text=True)
    assert counted.returncode == 0, counted.stderr
    assert int(counted.stdout.strip().splitlines()[-1]) >= 2, 'Expected at least parser and traversal unit tests.'

    result = subprocess.run(
        [sys.executable, '-m', 'unittest', test_file],
        cwd=HOME,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Student's unit tests failed:\n{result.stderr}\n{result.stdout}"


def test_server_does_not_start_when_imported():
    assert os.path.isfile(SERVER), f'{SERVER} does not exist or is not a file.'
    code = '''
import importlib.util
s = importlib.util.spec_from_file_location("student_server", "/home/user/server.py")
m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)
'''
    result = subprocess.run([sys.executable, '-c', code], cwd=HOME, capture_output=True, text=True, timeout=3)
    assert result.returncode == 0, f'Importing server.py failed or started the server:\n{result.stderr}'


async def ws_request(payload):
    async with websockets.connect('ws://localhost:8765') as websocket:
        await websocket.send(json.dumps(payload))
        return json.loads(await websocket.recv())


def run_server_queries(queries):
    process = subprocess.Popen(
        [sys.executable, SERVER], cwd=HOME,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    try:
        time.sleep(1.5)
        if process.poll() is not None:
            stdout, stderr = process.communicate()
            pytest.fail(f'Server crashed on startup. Return code: {process.returncode}\nStderr: {stderr.decode()}\nStdout: {stdout.decode()}')
        for payload, expected in queries:
            response = asyncio.run(ws_request(payload))
            assert response.get('path') == expected, f'For {payload}, expected {expected}, got {response}'
    finally:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=2)


def test_websocket_server_original_query():
    assert os.path.isfile(SERVER), f'Server file {SERVER} does not exist.'
    run_server_queries([
        ({'start': 'libfront.so', 'target': 'libbase.so'},
         ['libfront.so', 'libmiddle_b.so', 'libbase.so']),
    ])


def test_websocket_server_uses_dump_and_resolves_fresh_queries():
    tag = uuid.uuid4().hex
    a, b, c, d, e, z = [f'lib{x}_{tag}.so' for x in 'abcdez']
    graph = {
        a: [b, c],
        b: [d],
        c: [e],
        d: [e],
        e: [],
        z: [],
    }
    dynamic_dump = f'''[{a}]
    linux-vdso.so.1 =>  (0x1)
    {b} => /opt/{b} (0x2)
    {c} => /opt/{c} (0x3)
    libc.so.6 => /lib/libc.so.6 (0x4)
[{b}]
    {d} => /opt/{d} (0x5)
[{c}]
    {e} => /opt/{e} (0x6)
[{d}]
    {e} => /opt/{e} (0x7)
[{e}]
[{z}]
'''
    with open(DUMP, 'rb') as f:
        original = f.read()
    try:
        with open(DUMP, 'w') as f:
            f.write(dynamic_dump)
        pairs = [(a, e), (b, e), (c, d), (e, e), (z, a)]
        queries = [
            ({'start': start, 'target': target}, oracle_bfs(graph, start, target))
            for start, target in pairs
        ]
        run_server_queries(queries)
    finally:
        with open(DUMP, 'wb') as f:
            f.write(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
