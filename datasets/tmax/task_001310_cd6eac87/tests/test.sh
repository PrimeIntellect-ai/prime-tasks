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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import signal
import socket
import sqlite3
import subprocess
import time
import uuid
from pathlib import Path

import pytest
import requests

PROJECT = Path('/home/user/graph_api')
MANIFEST = PROJECT / 'Cargo.toml'
DATABASE = Path('/app/dataset.db')
BACKUP = Path('/tmp/dataset-verifier-backup.db')
URL = 'http://127.0.0.1:8080/top-affiliations'


def kill_port_8080():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].rsplit(':', 1)[-1].upper() == '1F90':
                inodes.add(fields[9])

    me = os.getpid()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name) == me:
            continue
        fd_dir = proc / 'fd'
        try:
            fds = list(fd_dir.iterdir())
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                try:
                    os.kill(int(proc.name), signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    time.sleep(0.3)


def backup_database():
    if BACKUP.exists():
        BACKUP.unlink()
    src = sqlite3.connect(str(DATABASE))
    dst = sqlite3.connect(str(BACKUP))
    try:
        src.backup(dst)
    finally:
        dst.close()
        src.close()


def restore_database():
    for suffix in ('', '-wal', '-shm'):
        try:
            Path(str(DATABASE) + suffix).unlink()
        except FileNotFoundError:
            pass
    shutil.copy2(BACKUP, DATABASE)


def build_rust_service():
    assert PROJECT.is_dir(), f'Missing Cargo project: {PROJECT}'
    assert MANIFEST.is_file(), f'Missing Cargo manifest: {MANIFEST}'
    rust_sources = list(PROJECT.rglob('*.rs'))
    assert rust_sources, 'Cargo project contains no Rust source files'

    metadata_result = subprocess.run(
        ['cargo', 'metadata', '--offline', '--no-deps', '--format-version', '1',
         '--manifest-path', str(MANIFEST)],
        cwd=PROJECT, text=True, capture_output=True, timeout=60
    )
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)
    root_packages = [p for p in metadata['packages']
                     if Path(p['manifest_path']).resolve() == MANIFEST.resolve()]
    assert len(root_packages) == 1, 'graph_api/Cargo.toml must define the service package'
    package_id = root_packages[0]['id']

    result = subprocess.run(
        ['cargo', 'build', '--offline', '--message-format=json',
         '--manifest-path', str(MANIFEST)],
        cwd=PROJECT, text=True, capture_output=True, timeout=240
    )
    assert result.returncode == 0, f'Cargo build failed:\n{result.stderr}\n{result.stdout}'

    executables = []
    for line in result.stdout.splitlines():
        try:
            message = json.loads(line)
        except ValueError:
            continue
        if (message.get('reason') == 'compiler-artifact'
                and message.get('package_id') == package_id
                and 'bin' in message.get('target', {}).get('kind', [])
                and message.get('executable')):
            executables.append(Path(message['executable']))

    assert executables, 'Cargo project did not build a Rust binary target'
    preferred = [p for p in executables if p.name == 'graph_api']
    executable = preferred[-1] if preferred else executables[-1]
    assert executable.is_file(), f'Built service binary is missing: {executable}'
    with executable.open('rb') as f:
        assert f.read(4) == b'\x7fELF', 'Built service is not an ELF executable'
    return executable


def start_service(executable):
    kill_port_8080()
    proc = subprocess.Popen(
        [str(executable)], cwd=PROJECT,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    deadline = time.time() + 12
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f'Rust service exited during startup with status {proc.returncode}')
        try:
            response = requests.get(URL, timeout=0.5)
            return proc, response
        except requests.exceptions.RequestException:
            time.sleep(0.2)
    proc.kill()
    proc.wait(timeout=5)
    pytest.fail(f'Failed to connect to the web service at {URL}')


def stop_service(proc):
    if proc is not None and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)
    kill_port_8080()


def assert_response(response, expected):
    assert response.status_code == 200, (
        f'Expected status code 200, got {response.status_code}. '
        f'Response body: {response.text}'
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f'Response is not valid JSON. Response body: {response.text}')
    assert data == expected, f'Expected JSON {expected}, got {data}'


def assert_exactly_one_endpoint():
    for path in ('/', '/health', '/favicon.ico', '/top-affiliation'):
        response = requests.get('http://127.0.0.1:8080' + path, timeout=3)
        assert response.status_code == 404, f'Unexpected GET endpoint {path}: {response.status_code}'
    response = requests.post(URL, timeout=3)
    assert response.status_code in (404, 405), (
        f'POST /top-affiliations unexpectedly succeeded with {response.status_code}'
    )


def install_random_fixture(variant):
    rng = random.SystemRandom()
    researcher_ids = ['researcher_' + uuid.uuid4().hex for _ in range(5)]
    institution_ids = ['institution_' + uuid.uuid4().hex for _ in range(6)]
    rng.shuffle(researcher_ids)
    rng.shuffle(institution_ids)

    researcher_regions = ['A', 'A', 'B', 'B', 'C']
    institution_regions = ['A', 'A', 'A', 'B', 'B', 'C']
    valid_limits = [3, 2, 2, 1, 1] if variant == 0 else [1, 3, 1, 2, 1]

    con = sqlite3.connect(str(DATABASE))
    try:
        con.execute('PRAGMA journal_mode=DELETE')
        con.execute('DELETE FROM edges')
        con.execute('DELETE FROM nodes')
        con.executemany(
            'INSERT INTO nodes(id, label, region) VALUES (?, ?, ?)',
            [(rid, 'researcher', region)
             for rid, region in zip(researcher_ids, researcher_regions)]
            + [(iid, 'institution', region)
               for iid, region in zip(institution_ids, institution_regions)]
        )

        edges = []
        for r_index, (rid, r_region) in enumerate(zip(researcher_ids, researcher_regions)):
            matching_seen = 0
            for iid, i_region in zip(institution_ids, institution_regions):
                if r_region != i_region:
                    edges.append((rid, iid, 'affiliated_with'))
                elif matching_seen < valid_limits[r_index]:
                    edges.append((rid, iid, 'affiliated_with'))
                    matching_seen += 1
        con.executemany('INSERT INTO edges(source, target, type) VALUES (?, ?, ?)', edges)
        con.commit()

        rows = con.execute('''
            SELECT r.id, COUNT(*) AS degree
            FROM edges e
            JOIN nodes r ON r.id = e.source AND r.label = 'researcher'
            JOIN nodes i ON i.id = e.target AND i.label = 'institution'
            WHERE e.type = 'affiliated_with' AND r.region = i.region
            GROUP BY r.id
            ORDER BY degree DESC, r.id ASC
            LIMIT 3
        ''').fetchall()
        return [[row[0], row[1]] for row in rows]
    finally:
        con.close()


def test_complete_rust_graph_service():
    backup_database()
    proc = None
    try:
        kill_port_8080()
        executable = build_rust_service()

        # Preserve the original verifier's assertion against the supplied dataset.
        restore_database()
        proc, response = start_service(executable)
        expected = [['r2', 3], ['r3', 3], ['r1', 2]]
        assert_response(response, expected)
        assert_exactly_one_endpoint()
        stop_service(proc)
        proc = None

        # Exercise the freshly built Rust artifact on unpredictable databases.
        for variant in (0, 1):
            restore_database()
            expected = install_random_fixture(variant)
            proc, response = start_service(executable)
            assert_response(response, expected)
            assert_exactly_one_endpoint()
            stop_service(proc)
            proc = None
    finally:
        stop_service(proc)
        if BACKUP.exists():
            restore_database()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
