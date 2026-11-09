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

cat <<'PYTEST' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import socket
import subprocess
import time
from pathlib import Path

import requests

BACKUPS = Path('/home/user/backups.json')
TARGET = 'D-94'


def listener_pids(port=8080):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == '0A':
                _, port_hex = fields[1].rsplit(':', 1)
                if int(port_hex, 16) == port:
                    inodes.add(fields[9])
    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    link = os.readlink(fd)
                except OSError:
                    continue
                if link.startswith('socket:[') and link[8:-1] in inodes:
                    pids.add(int(proc.name))
        except OSError:
            pass
    return pids


def stop_server():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listener_pids() and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_pids() and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_pids(), 'Could not free port 8080'


def wait_for_server(proc, timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            return False
        try:
            requests.get('http://127.0.0.1:8080/audit?page=1&limit=1', timeout=0.3)
            return True
        except requests.RequestException as exc:
            last_error = exc
            time.sleep(0.1)
    return False


def assert_strict_loopback_listener():
    listeners = []
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 4 and fields[3] == '0A':
                addr, port_hex = fields[1].rsplit(':', 1)
                if int(port_hex, 16) == 8080:
                    listeners.append((table, addr))
    assert listeners, 'No process is listening on port 8080'
    assert listeners == [('/proc/net/tcp', '0100007F')], (
        'Server must listen strictly on IPv4 127.0.0.1:8080; '
        f'observed listeners: {listeners}'
    )


def compile_and_start_cpp():
    sources = sorted(set(
        list(Path('/home/user').rglob('*.cpp')) +
        list(Path('/app').rglob('*.cpp'))
    ))
    assert sources, 'No C++ source file was submitted under /home/user or /app'

    compile_errors = []
    for index, source in enumerate(sources):
        output = Path(f'/tmp/audit_server_{index}')
        result = subprocess.run(
            ['g++', '-std=c++17', '-O2', '-pthread', '-I/home/user',
             str(source), '-o', str(output)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=90,
        )
        if result.returncode != 0:
            compile_errors.append(f'{source}:\n{result.stdout[-3000:]}')
            continue

        stop_server()
        proc = subprocess.Popen(
            [str(output)], cwd=str(source.parent),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if wait_for_server(proc):
            return source, output, proc
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=2)
        stop_server()

    raise AssertionError(
        'No submitted C++ source compiled into a working audit server.\n' +
        '\n'.join(compile_errors)
    )


def restart(executable):
    stop_server()
    proc = subprocess.Popen(
        [str(executable)], cwd='/home/user',
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    assert wait_for_server(proc), 'Compiled C++ server did not start after graph update'
    assert_strict_loopback_listener()
    return proc


def expected_records(graph):
    by_id = {item['id']: item for item in graph}
    children = {}
    for item in graph:
        children.setdefault(item.get('parent_id'), []).append(item['id'])
    assert TARGET in by_id

    found = []
    stack = [TARGET]
    seen = set()
    while stack:
        node_id = stack.pop()
        if node_id in seen:
            continue
        seen.add(node_id)
        node = by_id[node_id]
        if node['status'] == 'SUCCESS':
            found.append({'id': node['id'], 'timestamp': node['timestamp']})
        stack.extend(children.get(node_id, []))
    return sorted(found, key=lambda item: item['timestamp'], reverse=True)


def check_page(records, page, limit):
    response = requests.get(
        'http://127.0.0.1:8080/audit',
        params={'page': page, 'limit': limit},
        timeout=5,
    )
    assert response.status_code == 200, response.text
    assert response.headers.get('content-type', '').split(';')[0].strip().lower() == 'application/json'
    try:
        actual = response.json()
    except ValueError as exc:
        raise AssertionError(f'Response is not valid JSON: {response.text}') from exc

    expected = {
        'data': records[(page - 1) * limit:page * limit],
        'total_descendants': len(records),
        'page': page,
    }
    assert actual == expected, f'Expected {expected}, got {actual}'
    assert set(actual) == {'data', 'total_descendants', 'page'}
    assert type(actual['total_descendants']) is int
    assert type(actual['page']) is int
    for item in actual['data']:
        assert set(item) == {'id', 'timestamp'}
        assert type(item['id']) is str
        assert type(item['timestamp']) in (int, float) and not isinstance(item['timestamp'], bool)


def main():
    original = BACKUPS.read_bytes()
    processes = []
    try:
        baseline = json.loads(original)
        baseline_records = expected_records(baseline)
        source, executable, proc = compile_and_start_cpp()
        processes.append(proc)
        assert_strict_loopback_listener()

        # Preserve the original two pagination checks, corrected to include the
        # successful target node as required by the instruction.
        check_page(baseline_records, 1, 2)
        check_page(baseline_records, 2, 2)
        check_page(baseline_records, 2, 3)
        check_page(baseline_records, 4, 2)

        token = secrets.token_hex(5).upper()
        base = int(time.time()) + secrets.randbelow(100000)
        dynamic_graph = [
            {'id': 'ROOT-' + token, 'parent_id': None, 'timestamp': base - 100, 'status': 'SUCCESS'},
            {'id': TARGET, 'parent_id': 'ROOT-' + token, 'timestamp': base + 11, 'status': 'SUCCESS'},
            {'id': 'DIRECT-' + token, 'parent_id': TARGET, 'timestamp': base + 701, 'status': 'SUCCESS'},
            {'id': 'FAILED-' + token, 'parent_id': TARGET, 'timestamp': base + 902, 'status': 'FAILED'},
            {'id': 'THROUGH-' + token, 'parent_id': 'FAILED-' + token, 'timestamp': base + 1203, 'status': 'SUCCESS'},
            {'id': 'DEEP-' + token, 'parent_id': 'DIRECT-' + token, 'timestamp': base + 405, 'status': 'SUCCESS'},
            {'id': 'OTHER-' + token, 'parent_id': 'ROOT-' + token, 'timestamp': base + 5000, 'status': 'SUCCESS'},
        ]
        BACKUPS.write_text(json.dumps(dynamic_graph))
        proc = restart(executable)
        processes.append(proc)
        dynamic_records = expected_records(dynamic_graph)

        for page, limit in ((1, 1), (1, 3), (2, 2), (2, 3), (5, 2)):
            check_page(dynamic_records, page, limit)
    finally:
        BACKUPS.write_bytes(original)
        stop_server()
        for proc in processes:
            if proc.poll() is None:
                try:
                    proc.kill()
                except ProcessLookupError:
                    pass


if __name__ == '__main__':
    main()
PYTEST

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
