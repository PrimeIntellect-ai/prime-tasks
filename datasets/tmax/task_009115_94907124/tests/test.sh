#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import secrets
import select
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import pytest

APP = Path('/home/user/app')
EXT = APP / 'ext'
DB = APP / 'db' / 'chat.db'


def inspect_extension(path):
    path = Path(path)
    assert path.is_file(), f'Extension artifact is missing: {path}'
    assert path.suffix == '.so' or '.so.' in path.name, f'{path} is not a compiled extension.'

    result = subprocess.run(
        ['readelf', '-d', str(path)], capture_output=True, text=True
    )
    assert result.returncode == 0, f'{path} is not a readable ELF shared object:\n{result.stderr}'
    dynamic = result.stdout
    assert re.search(r'NEEDED.*\[libcustomsec\.so\]', dynamic), (
        'The extension is not dynamically linked to libcustomsec.so.'
    )

    search_paths = []
    for line in dynamic.splitlines():
        if '(RPATH)' in line or '(RUNPATH)' in line:
            match = re.search(r'\[(.*?)\]', line)
            if match:
                search_paths.extend(match.group(1).split(':'))
    assert '/home/user/app/lib' in search_paths, (
        'The extension does not embed the exact runtime search path /home/user/app/lib.'
    )


def isolated_import(module_dir=None):
    samples = [
        'audit_' + secrets.token_hex(6),
        'value-' + secrets.token_hex(5),
        'spaces ' + secrets.token_hex(4),
    ]
    code = r'''
import json, sys
module_dir = json.loads(sys.argv[1])
if module_dir is not None:
    sys.path.insert(0, module_dir)
import sec_ext
samples = json.loads(sys.argv[2])
print(json.dumps({'file': sec_ext.__file__, 'values': [sec_ext.compute_hash(x) for x in samples]}))
'''
    env = os.environ.copy()
    env.pop('LD_LIBRARY_PATH', None)
    env.pop('PYTHONPATH', None)
    result = subprocess.run(
        [sys.executable, '-I', '-c', code, json.dumps(module_dir), json.dumps(samples)],
        cwd='/tmp', env=env, capture_output=True, text=True
    )
    assert result.returncode == 0, (
        'sec_ext could not be imported with LD_LIBRARY_PATH unset:\n'
        + result.stdout + '\n' + result.stderr
    )
    try:
        report = json.loads(result.stdout.strip().splitlines()[-1])
    except Exception as exc:
        pytest.fail(f'Could not read sec_ext import report: {exc}\n{result.stdout}')
    assert report['values'] == [value + '_hashed' for value in samples], (
        'sec_ext.compute_hash does not invoke the expected custom-library behavior.'
    )
    inspect_extension(report['file'])


def test_task1_extension_installed():
    # Preserve the original global-import assertion.
    original_path = sys.path.copy()
    try:
        sys.path = [p for p in sys.path if not p.startswith('/home/user/app/ext')]
        try:
            import sec_ext
        except ImportError as e:
            pytest.fail(f'Failed to import sec_ext: {e}. Ensure it is installed globally and linked correctly.')
    finally:
        sys.path = original_path

    setup_py_path = '/home/user/app/ext/setup.py'
    assert os.path.isfile(setup_py_path), 'setup.py is missing.'
    with open(setup_py_path, 'r') as f:
        content = f.read()
        assert 'runtime_library_dirs' in content or '-Wl,-rpath' in content, 'setup.py does not contain rpath configuration.'

    # Import the globally installed artifact in an isolated interpreter without
    # relying on LD_LIBRARY_PATH, then inspect its actual ELF linkage.
    isolated_import()

    # Execute the submitted build script and validate the artifact it produces.
    with tempfile.TemporaryDirectory(prefix='sec-build-') as td:
        build_lib = Path(td) / 'lib'
        build_temp = Path(td) / 'temp'
        result = subprocess.run(
            [sys.executable, 'setup.py', 'build_ext', '--force',
             '--build-lib', str(build_lib), '--build-temp', str(build_temp)],
            cwd=str(EXT), capture_output=True, text=True,
            env={k: v for k, v in os.environ.items() if k != 'LD_LIBRARY_PATH'}
        )
        assert result.returncode == 0, f'setup.py failed to build the extension:\n{result.stdout}\n{result.stderr}'
        artifacts = list(build_lib.rglob('sec_ext*.so'))
        assert artifacts, 'setup.py did not produce a sec_ext compiled extension.'
        inspect_extension(artifacts[0])
        isolated_import(str(build_lib))


def test_task2_database_migration():
    assert DB.is_file(), f'Database file {DB} is missing.'
    migrate = APP / 'migrate.py'
    assert migrate.is_file(), f'{migrate} is missing.'
    ast.parse(migrate.read_text(), filename=str(migrate))

    conn = sqlite3.connect(DB)
    try:
        cursor = conn.cursor()
        cursor.execute('PRAGMA table_info(messages)')
        columns = [row[1] for row in cursor.fetchall()]
        assert 'msg_hash' in columns, "Column 'msg_hash' was not added to 'messages' table."

        cursor.execute('SELECT id, content, msg_hash FROM messages ORDER BY id')
        rows = cursor.fetchall()
        assert len(rows) == 2, 'The migration must preserve the two original message rows.'
        assert [(row[0], row[1]) for row in rows] == [
            (1, 'Hello world'), (2, 'Secure message')
        ], 'The original message IDs and contents were not preserved.'

        import sec_ext
        for _, content, msg_hash in rows:
            expected_hash = sec_ext.compute_hash(content)
            assert msg_hash == expected_hash, f"Hash mismatch for content '{content}'. Expected {expected_hash}, got {msg_hash}."
            assert msg_hash == content + '_hashed', 'Hash was not independently verified.'
    finally:
        conn.close()

    # Exercise migrate.py itself against a fresh database at the instructed path,
    # restoring the submitted database afterward.
    backup = Path(tempfile.mktemp(prefix='chat-backup-', suffix='.db'))
    shutil.copy2(DB, backup)
    probe_rows = [
        (17, 'probe-' + secrets.token_hex(5)),
        (41, 'second ' + secrets.token_hex(5)),
    ]
    try:
        for suffix in ('', '-wal', '-shm'):
            try:
                Path(str(DB) + suffix).unlink()
            except FileNotFoundError:
                pass
        conn = sqlite3.connect(DB)
        try:
            conn.execute('CREATE TABLE messages (id INTEGER PRIMARY KEY, content TEXT)')
            conn.executemany('INSERT INTO messages (id, content) VALUES (?, ?)', probe_rows)
            conn.commit()
        finally:
            conn.close()

        env = os.environ.copy()
        env.pop('LD_LIBRARY_PATH', None)
        result = subprocess.run(
            [sys.executable, str(migrate)], cwd=str(APP), env=env,
            capture_output=True, text=True
        )
        assert result.returncode == 0, f'migrate.py failed on an unmigrated database:\n{result.stdout}\n{result.stderr}'

        conn = sqlite3.connect(DB)
        try:
            columns = [row[1] for row in conn.execute('PRAGMA table_info(messages)')]
            assert 'msg_hash' in columns, 'migrate.py did not add msg_hash.'
            migrated = conn.execute(
                'SELECT id, content, msg_hash FROM messages ORDER BY id'
            ).fetchall()
        finally:
            conn.close()
        assert [(r[0], r[1]) for r in migrated] == probe_rows, (
            'migrate.py deleted or changed existing rows.'
        )
        assert [r[2] for r in migrated] == [content + '_hashed' for _, content in probe_rows], (
            'migrate.py did not correctly backfill every existing row.'
        )
    finally:
        for suffix in ('', '-wal', '-shm'):
            try:
                Path(str(DB) + suffix).unlink()
            except FileNotFoundError:
                pass
        shutil.move(str(backup), str(DB))


def test_task3_test_ws_script():
    test_script_path = '/home/user/app/test_ws.py'
    assert os.path.isfile(test_script_path), f'{test_script_path} is missing.'

    with open(test_script_path, 'r') as f:
        content = f.read()

    # Preserve the original source and collection assertions.
    assert 'import pytest' in content, 'test_ws.py must import pytest.'
    assert 'hypothesis' in content, 'test_ws.py must use hypothesis.'
    assert '@given' in content, 'test_ws.py must use @given from hypothesis.'
    assert 'st.integers' in content, 'test_ws.py must use st.integers().'
    assert 'st.text' in content, 'test_ws.py must use st.text().'
    assert 'ws://localhost:8080' in content, 'test_ws.py must connect to ws://localhost:8080.'

    tree = ast.parse(content, filename=test_script_path)
    functions = [n for n in tree.body if isinstance(n, ast.AsyncFunctionDef) and n.name == 'test_websocket_payloads']
    assert functions, 'test_websocket_payloads must be an async test function.'
    function = functions[0]
    awaited_methods = {
        node.value.func.attr
        for node in ast.walk(function)
        if isinstance(node, ast.Await)
        and isinstance(node.value, ast.Call)
        and isinstance(node.value.func, ast.Attribute)
    }
    assert 'send' in awaited_methods, 'test_websocket_payloads must await sending WebSocket data.'
    assert 'recv' in awaited_methods or any(isinstance(n, ast.AsyncFor) for n in ast.walk(function)), (
        'test_websocket_payloads must read a response from the WebSocket.'
    )

    result = subprocess.run(
        ['pytest', test_script_path, '--collect-only'], capture_output=True, text=True
    )
    assert result.returncode == 0, f'pytest failed to collect tests from {test_script_path}:\n{result.stderr}\n{result.stdout}'

    with tempfile.TemporaryDirectory(prefix='ws-audit-') as td:
        log_path = Path(td) / 'messages.jsonl'
        server_path = Path(td) / 'server.py'
        server_path.write_text(r'''
import asyncio
import json
import sys
from websockets.asyncio.server import serve

log_path = sys.argv[1]

async def handler(ws):
    try:
        raw = await ws.recv()
        payload = json.loads(raw)
        if not isinstance(payload, dict):
            await ws.close(code=1003)
            return
        if set(payload) != {'id', 'content'} or isinstance(payload['id'], bool) or not isinstance(payload['id'], int) or not isinstance(payload['content'], str):
            await ws.close(code=1003)
            return
        with open(log_path, 'a', encoding='utf-8') as out:
            out.write(json.dumps(payload, ensure_ascii=False) + '\n')
            out.flush()
        await ws.send(json.dumps({'accepted': True, 'id': payload['id']}))
    except Exception:
        try:
            await ws.close(code=1011)
        except Exception:
            pass

async def main():
    async with serve(handler, '127.0.0.1', 8080):
        print('READY', flush=True)
        await asyncio.Future()

asyncio.run(main())
''')
        server = subprocess.Popen(
            [sys.executable, str(server_path), str(log_path)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        try:
            ready, _, _ = select.select([server.stdout], [], [], 10)
            assert ready and server.stdout.readline().strip() == 'READY', (
                'Could not start the verifier WebSocket server on localhost:8080.'
            )
            run = subprocess.run(
                ['pytest', '-q', test_script_path], capture_output=True, text=True,
                timeout=90, env={**os.environ, 'HYPOTHESIS_DATABASE_FILE': os.devnull}
            )
            assert run.returncode == 0, f'test_ws.py failed against a real WebSocket server:\n{run.stdout}\n{run.stderr}'
        finally:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)

        assert log_path.is_file(), 'The test never sent a payload to the WebSocket server.'
        payloads = [json.loads(line) for line in log_path.read_text().splitlines() if line.strip()]
        assert len(payloads) >= 2, 'The property-based test must exercise more than one generated payload.'
        assert all(
            set(p) == {'id', 'content'}
            and isinstance(p['id'], int) and not isinstance(p['id'], bool)
            and isinstance(p['content'], str)
            for p in payloads
        ), 'Sent payloads must contain an integer id and string content.'
        assert len({json.dumps(p, sort_keys=True, ensure_ascii=False) for p in payloads}) >= 2, (
            'The test did not send varied Hypothesis-generated payloads.'
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
