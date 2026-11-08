#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import stat
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

import grpc

BUILDER_DIR = Path('/home/user/legacy_builder')
BUILDER = BUILDER_DIR / 'builder'
DB = Path('/home/user/db/artifacts.db')
MIGRATE = Path('/home/user/db/migrate.py')
GRPC_DIR = Path('/home/user/grpc')
JSON_PATH = Path('/home/user/final_artifacts.json')


def reset_legacy_database():
    if DB.exists():
        DB.unlink()
    conn = sqlite3.connect(DB)
    conn.execute('CREATE TABLE artifacts (id INTEGER PRIMARY KEY, name TEXT, size INTEGER)')
    conn.execute("INSERT INTO artifacts (name, size) VALUES ('legacy_core', 45000)")
    conn.commit()
    conn.close()


def run_migration_and_check():
    assert MIGRATE.is_file(), f'{MIGRATE} does not exist.'
    subprocess.run([sys.executable, str(MIGRATE)], cwd=str(MIGRATE.parent), check=True, timeout=15)

    conn = sqlite3.connect(DB)
    try:
        assert conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='artifacts'").fetchone() is None, 'The old artifacts table was not dropped.'
        assert conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='artifacts_v2'").fetchone() is not None, 'The artifacts_v2 table does not exist.'
        info = conn.execute('PRAGMA table_info(artifacts_v2)').fetchall()
        columns = {row[1]: row[2].upper() for row in info}
        expected_columns = {'id', 'name', 'size', 'checksum', 'status'}
        assert set(columns) == expected_columns, f'Expected columns {expected_columns}, found {set(columns)}.'
        assert columns == {'id': 'INTEGER', 'name': 'TEXT', 'size': 'INTEGER', 'checksum': 'TEXT', 'status': 'TEXT'}
        id_info = next(row for row in info if row[1] == 'id')
        assert id_info[5] == 1, 'id is not the primary key.'
        assert conn.execute('SELECT id, name, size, checksum, status FROM artifacts_v2').fetchall() == [
            (1, 'legacy_core', 45000, None, None)
        ], 'The existing artifact was not migrated correctly.'
    finally:
        conn.close()


def start_server():
    env = os.environ.copy()
    env['PYTHONPATH'] = str(GRPC_DIR) + os.pathsep + env.get('PYTHONPATH', '')
    proc = subprocess.Popen(
        [sys.executable, str(GRPC_DIR / 'server.py')],
        cwd=str(GRPC_DIR), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    channel = grpc.insecure_channel('localhost:50051')
    try:
        grpc.channel_ready_future(channel).result(timeout=10)
    except Exception:
        proc.terminate()
        out, err = proc.communicate(timeout=5)
        raise AssertionError(f'gRPC server did not become ready. stdout={out!r}, stderr={err!r}')
    assert proc.poll() is None, 'server.py exited instead of serving requests.'
    return proc, channel


def stop_server(proc, channel):
    channel.close()
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
    time.sleep(0.3)


def read_rows():
    conn = sqlite3.connect(DB)
    try:
        return conn.execute('SELECT id, name, size, checksum, status FROM artifacts_v2 ORDER BY id').fetchall()
    finally:
        conn.close()


def test_complete_pipeline():
    # Running make must really rebuild main.c into a native executable.
    assert (BUILDER_DIR / 'Makefile').is_file(), 'Makefile does not exist.'
    if BUILDER.exists():
        BUILDER.unlink()
    subprocess.run(['make'], cwd=str(BUILDER_DIR), check=True, timeout=20)
    assert BUILDER.exists(), f'The compiled executable {BUILDER} does not exist.'
    assert BUILDER.is_file(), f'{BUILDER} is not a file.'
    st = BUILDER.stat()
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f'{BUILDER} is not executable.'
    assert BUILDER.read_bytes()[:4] == b'\x7fELF', 'make did not produce a native compiled executable.'
    built = subprocess.run([str(BUILDER)], check=True, capture_output=True, text=True, timeout=10)
    assert '>>> BEGIN_ARTIFACT' in built.stdout and '<<< END_ARTIFACT' in built.stdout
    assert 'NAME: service_alpha_bin' in built.stdout and 'NAME: service_beta_bin' in built.stdout

    # The submitted proto must compile and define the requested API, and generated bindings must exist.
    proto = GRPC_DIR / 'builder.proto'
    pb2_path = GRPC_DIR / 'builder_pb2.py'
    pb2_grpc_path = GRPC_DIR / 'builder_pb2_grpc.py'
    for path in (proto, pb2_path, pb2_grpc_path, GRPC_DIR / 'server.py', GRPC_DIR / 'client.py'):
        assert path.is_file(), f'{path} does not exist.'
    with tempfile.TemporaryDirectory() as outdir:
        result = subprocess.run([
            sys.executable, '-m', 'grpc_tools.protoc',
            f'-I{GRPC_DIR}', f'--python_out={outdir}', f'--grpc_python_out={outdir}', str(proto)
        ], capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, f'builder.proto does not compile: {result.stderr}'

    sys.path.insert(0, str(GRPC_DIR))
    import builder_pb2
    import builder_pb2_grpc

    service = builder_pb2.DESCRIPTOR.services_by_name.get('ArtifactBuilder')
    assert builder_pb2.DESCRIPTOR.package == 'buildsys'
    assert service is not None and len(service.methods) == 1
    method = service.methods[0]
    assert method.name == 'BuildArtifact'
    assert method.input_type.full_name == 'buildsys.BuildRequest'
    assert method.output_type.full_name == 'buildsys.BuildResponse'
    success_field = method.output_type.fields_by_name.get('success')
    assert success_field is not None and success_field.number == 1 and success_field.type == success_field.TYPE_BOOL

    # Execute the migration from the supplied legacy state.
    reset_legacy_database()
    run_migration_and_check()

    # Replace only the already-validated compiled builder temporarily with unpredictable
    # output. This proves the server executes it and parses records between the markers.
    original_builder = BUILDER.read_bytes()
    original_mode = BUILDER.stat().st_mode
    token = uuid.uuid4().hex
    name1 = 'dynamic_' + token[:10]
    name2 = 'dynamic_' + token[10:20]
    hash1 = token[20:] + 'a'
    hash2 = token[:16] + 'b'
    size1 = 51000 + int(token[:3], 16)
    size2 = 91000 + int(token[3:6], 16)
    script = f'''#!/bin/sh
printf '%s\\n' 'NAME: outside_must_be_ignored' 'SIZE: 999999' 'HASH: outside_hash'
printf '%s\\n' 'noise before' '>>> BEGIN_ARTIFACT' 'NAME: {name1}' 'SIZE: {size1}' 'HASH: {hash1}' '<<< END_ARTIFACT'
printf '%s\\n' 'unrelated output' '>>> BEGIN_ARTIFACT' 'NAME: {name2}' 'SIZE: {size2}' 'HASH: {hash2}' '<<< END_ARTIFACT' 'noise after'
'''
    BUILDER.write_text(script)
    BUILDER.chmod(0o755)

    expected_dynamic = [
        (1, 'legacy_core', 45000, None, None),
        (2, name1, size1, hash1, 'BUILT'),
        (3, name2, size2, hash2, 'BUILT'),
    ]

    proc = channel = None
    try:
        proc, channel = start_server()
        stub = builder_pb2_grpc.ArtifactBuilderStub(channel)
        response = stub.BuildArtifact(builder_pb2.BuildRequest(), timeout=10)
        assert response.success is True, 'BuildArtifact did not return success=True.'
        assert read_rows() == expected_dynamic, 'The server did not parse and insert the dynamic builder output correctly.'

        # Exercise the submitted client against the live server and ensure it exports
        # current database contents rather than a fixed JSON answer.
        conn = sqlite3.connect(DB)
        conn.execute('DELETE FROM artifacts_v2 WHERE id > 1')
        conn.commit()
        conn.close()
        env = os.environ.copy()
        env['PYTHONPATH'] = str(GRPC_DIR) + os.pathsep + env.get('PYTHONPATH', '')
        subprocess.run([sys.executable, str(GRPC_DIR / 'client.py')], cwd=str(GRPC_DIR), env=env, check=True, timeout=15)
        assert read_rows() == expected_dynamic
        with JSON_PATH.open() as f:
            dynamic_json = json.load(f)
        assert dynamic_json == [
            {'id': row[0], 'name': row[1], 'size': row[2], 'checksum': row[3], 'status': row[4]}
            for row in expected_dynamic
        ], 'client.py did not export the current dynamic database rows.'
    finally:
        if proc is not None:
            stop_server(proc, channel)
        BUILDER.write_bytes(original_builder)
        BUILDER.chmod(stat.S_IMODE(original_mode))

    # Re-run the complete requested pipeline with the real compiled builder, leaving
    # the final state expected by the original assertions.
    reset_legacy_database()
    run_migration_and_check()
    proc, channel = start_server()
    try:
        env = os.environ.copy()
        env['PYTHONPATH'] = str(GRPC_DIR) + os.pathsep + env.get('PYTHONPATH', '')
        subprocess.run([sys.executable, str(GRPC_DIR / 'client.py')], cwd=str(GRPC_DIR), env=env, check=True, timeout=15)
    finally:
        stop_server(proc, channel)

    expected_rows = [
        (1, 'legacy_core', 45000, None, None),
        (2, 'service_alpha_bin', 84500, 'a1b2c3d4e5', 'BUILT'),
        (3, 'service_beta_bin', 128000, 'f6g7h8i9j0', 'BUILT'),
    ]
    assert read_rows() == expected_rows

    assert JSON_PATH.exists(), f'The output JSON file {JSON_PATH} does not exist.'
    with JSON_PATH.open() as f:
        data = json.load(f)
    assert isinstance(data, list), 'The JSON data should be a list of objects.'
    assert len(data) == 3, f'Expected 3 artifacts in the JSON output, found {len(data)}.'
    data_sorted = sorted(data, key=lambda x: x.get('id', 0))
    expected_data = [
        {'id': 1, 'name': 'legacy_core', 'size': 45000, 'checksum': None, 'status': None},
        {'id': 2, 'name': 'service_alpha_bin', 'size': 84500, 'checksum': 'a1b2c3d4e5', 'status': 'BUILT'},
        {'id': 3, 'name': 'service_beta_bin', 'size': 128000, 'checksum': 'f6g7h8i9j0', 'status': 'BUILT'},
    ]
    for i, (actual, expected) in enumerate(zip(data_sorted, expected_data)):
        for key in expected:
            assert key in actual, f"Missing key '{key}' in artifact {i + 1}."
            assert actual[key] == expected[key], f"Mismatch in artifact {i + 1} for key '{key}': expected {expected[key]}, got {actual[key]}."
    assert data_sorted == [
        {'id': row[0], 'name': row[1], 'size': row[2], 'checksum': row[3], 'status': row[4]}
        for row in expected_rows
    ], 'The final JSON does not reflect the current database rows.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
