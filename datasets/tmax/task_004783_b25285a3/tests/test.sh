#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.util
import inspect
import json
import os
import secrets
import shutil
import signal
import socket
import sqlite3
import subprocess
import sys
import time
import uuid

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
LIB_PATH = "/app/bin/libaudiofeat.so"
DB_PATH = "/app/data/ci_service.db"
WRAPPER_PATH = "/app/service/ffi_wrapper.py"
SERVER_PATH = "/app/service/server.py"


def expected_feature(path):
    return float(os.path.getsize(path) % 1000) + 0.5


def load_wrapper():
    name = "submitted_ffi_wrapper_" + uuid.uuid4().hex
    spec = importlib.util.spec_from_file_location(name, WRAPPER_PATH)
    assert spec and spec.loader, "Could not load /app/service/ffi_wrapper.py"
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def wrapper_results(module, path):
    results = []
    for _, func in inspect.getmembers(module, inspect.isfunction):
        if getattr(func, "__module__", None) != module.__name__:
            continue
        try:
            sig = inspect.signature(func)
            required = [p for p in sig.parameters.values()
                        if p.default is inspect.Parameter.empty
                        and p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]
            if len(required) <= 1:
                results.append(func(path))
        except Exception:
            pass

    for _, cls in inspect.getmembers(module, inspect.isclass):
        if getattr(cls, "__module__", None) != module.__name__:
            continue
        try:
            instance = cls()
        except Exception:
            continue
        for _, method in inspect.getmembers(instance, callable):
            if getattr(method, "__name__", "").startswith("_"):
                continue
            try:
                sig = inspect.signature(method)
                required = [p for p in sig.parameters.values()
                            if p.default is inspect.Parameter.empty
                            and p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]
                if len(required) <= 1:
                    results.append(method(path))
            except Exception:
                pass
    return results


def assert_wrapper_value(path, expected):
    module = load_wrapper()
    results = wrapper_results(module, path)
    assert results, "The FFI wrapper exposes no callable that accepts an audio filepath"
    assert any(isinstance(value, (int, float)) and abs(float(value) - expected) < 1e-5
               for value in results), (
        f"No callable in ffi_wrapper.py returned the C library value {expected}; got {results}"
    )


def db_row(job_id):
    with sqlite3.connect(DB_PATH) as conn:
        return conn.execute(
            "SELECT id, filepath, feature_value, status FROM jobs WHERE id = ?",
            (job_id,),
        ).fetchone()


def process_and_check(path, expected):
    response = requests.post(BASE_URL + "/process", json={"filepath": path}, timeout=5)
    assert response.status_code in (200, 201), (
        f"Expected HTTP 200/201 from POST /process, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        posted = response.json()
    except Exception:
        pytest.fail(f"POST /process did not return valid JSON. Response: {response.text}")
    assert "job_id" in posted, f"POST /process response missing 'job_id'. Response: {posted}"
    job_id = posted["job_id"]
    assert isinstance(job_id, int), f"job_id must be an integer, got {job_id!r}"

    response = requests.get(f"{BASE_URL}/job/{job_id}", timeout=5)
    assert response.status_code == 200, (
        f"Expected HTTP 200 from GET /job/{job_id}, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        job = response.json()
    except Exception:
        pytest.fail(f"GET /job/{job_id} did not return valid JSON. Response: {response.text}")

    assert job.get("id") == job_id, f"Expected id {job_id}, got {job.get('id')}"
    assert job.get("filepath") == path, f"Expected filepath {path!r}, got {job.get('filepath')!r}"
    assert abs(float(job.get("feature_value")) - expected) < 1e-5, (
        f"Expected feature_value {expected}, got {job.get('feature_value')}"
    )
    assert job.get("status") == "COMPLETED", (
        f"Expected status 'COMPLETED', got {job.get('status')}"
    )

    row = db_row(job_id)
    assert row is not None, f"POST /process did not persist job {job_id} in SQLite"
    assert row[0] == job_id
    assert row[1] == path
    assert abs(float(row[2]) - expected) < 1e-5
    assert row[3] == "COMPLETED"
    return job_id


def listening_pids(port=8080):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    parts = line.split()
                    if len(parts) > 9 and parts[3] == "0A":
                        if int(parts[1].rsplit(":", 1)[1], 16) == port:
                            inodes.add(parts[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except OSError:
            pass
    return pids


def stop_listener():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        deadline = time.time() + 3
        while time.time() < deadline:
            pids = listening_pids()
            if not pids:
                return
            for pid in pids:
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
            time.sleep(0.1)
    assert not listening_pids(), "Could not stop the submitted server on port 8080"


def start_submitted_server():
    log = open("/app/logs/server.log", "ab", buffering=0)
    env = os.environ.copy()
    env["PYTHONPATH"] = "/app:/app/service" + (
        ":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )
    proc = subprocess.Popen(
        [sys.executable, SERVER_PATH], cwd="/app", stdout=log,
        stderr=subprocess.STDOUT, env=env, start_new_session=True,
    )
    deadline = time.time() + 10
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"server.py exited during startup with status {proc.returncode}")
        try:
            requests.get(BASE_URL + "/job/999999999", timeout=0.4)
            return proc
        except requests.RequestException:
            time.sleep(0.1)
    pytest.fail("server.py did not begin listening on 127.0.0.1:8080")


def probe_wrapper_in_fresh_process(path, expected):
    probe = r'''
import importlib.util, inspect, sys, uuid
path, audio, expected = sys.argv[1], sys.argv[2], float(sys.argv[3])
name = "probe_" + uuid.uuid4().hex
spec = importlib.util.spec_from_file_location(name, path)
module = importlib.util.module_from_spec(spec)
sys.modules[name] = module
spec.loader.exec_module(module)
values = []
for _, func in inspect.getmembers(module, inspect.isfunction):
    if getattr(func, "__module__", None) != module.__name__: continue
    try:
        req = [p for p in inspect.signature(func).parameters.values()
               if p.default is inspect.Parameter.empty and
               p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]
        if len(req) <= 1: values.append(func(audio))
    except Exception: pass
for _, cls in inspect.getmembers(module, inspect.isclass):
    if getattr(cls, "__module__", None) != module.__name__: continue
    try: obj = cls()
    except Exception: continue
    for n, method in inspect.getmembers(obj, callable):
        if n.startswith("_"): continue
        try:
            req = [p for p in inspect.signature(method).parameters.values()
                   if p.default is inspect.Parameter.empty and
                   p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]
            if len(req) <= 1: values.append(method(audio))
        except Exception: pass
if not any(isinstance(v, (int, float)) and abs(float(v)-expected) < 1e-5 for v in values):
    raise SystemExit("wrapper did not return expected value; got %r" % (values,))
'''
    result = subprocess.run(
        [sys.executable, "-c", probe, WRAPPER_PATH, path, str(expected)],
        cwd="/app", env={**os.environ, "PYTHONPATH": "/app:/app/service"},
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    assert result.returncode == 0, result.stdout


def test_shared_library_exists_and_works(tmp_path):
    assert os.path.isfile(LIB_PATH), "/app/bin/libaudiofeat.so does not exist. Did you compile the C library?"
    lib = ctypes.CDLL(LIB_PATH)
    func = lib.get_audio_feature
    func.argtypes = [ctypes.c_char_p]
    func.restype = ctypes.c_float
    for i in range(3):
        fixture = tmp_path / f"direct_{i}_{uuid.uuid4().hex}.wav"
        fixture.write_bytes(os.urandom(secrets.randbelow(3500) + 17))
        expected = expected_feature(str(fixture))
        actual = float(func(os.fsencode(str(fixture))))
        assert abs(actual - expected) < 1e-5, (
            f"get_audio_feature returned {actual} for {fixture}, expected {expected}"
        )


def test_wrapper_exists_uses_ctypes_and_works(tmp_path):
    assert os.path.isfile(WRAPPER_PATH), "/app/service/ffi_wrapper.py does not exist"
    source = open(WRAPPER_PATH, encoding="utf-8").read()
    assert "ctypes" in source, "ffi_wrapper.py must use ctypes"
    fixture = tmp_path / ("wrapper_" + uuid.uuid4().hex + ".wav")
    fixture.write_bytes(os.urandom(secrets.randbelow(2800) + 31))
    assert_wrapper_value(str(fixture), expected_feature(str(fixture)))


def test_database_exists():
    assert os.path.isfile(DB_PATH), "/app/data/ci_service.db does not exist. Did you run the schema migrations?"


def test_server_log_exists():
    assert os.path.isfile("/app/logs/server.log"), "/app/logs/server.log does not exist. Is the server logging to this file?"


def test_database_schema():
    with sqlite3.connect(DB_PATH) as conn:
        rows = conn.execute("PRAGMA table_info(jobs)").fetchall()
        columns = {row[1] for row in rows}
        expected_columns = {"id", "filepath", "feature_value", "status"}
        missing = expected_columns - columns
        assert not missing, f"Database table 'jobs' is missing columns: {missing}. Did you apply all migrations?"
        assert [row[1] for row in rows] == ["id", "filepath", "feature_value", "status"], (
            "jobs columns are not in the order produced by 001_init.sql then 002_add_columns.sql"
        )
        info = {row[1]: row for row in rows}
        assert info["id"][2].upper() == "INTEGER" and info["id"][5] == 1
        assert info["filepath"][2].upper() == "TEXT" and info["filepath"][3] == 1
        sequence = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='sqlite_sequence'"
        ).fetchone()
        assert sequence is not None, "jobs.id was not created with AUTOINCREMENT"


def test_api_process_and_get_dynamic(tmp_path):
    assert os.path.isfile(SERVER_PATH), "/app/service/server.py does not exist"

    # Retain the provided-fixture check from the original verifier.
    original_expected = expected_feature("/app/test_audio.wav")
    process_and_check("/app/test_audio.wav", original_expected)

    ids = []
    used_moduli = set()
    for i in range(3):
        while True:
            size = secrets.randbelow(6000) + 1
            if size % 1000 not in used_moduli:
                used_moduli.add(size % 1000)
                break
        fixture = tmp_path / f"api_{i}_{uuid.uuid4().hex}.wav"
        fixture.write_bytes(os.urandom(size))
        ids.append(process_and_check(str(fixture), expected_feature(str(fixture))))
    assert len(set(ids)) == len(ids), "POST /process reused job IDs instead of inserting new rows"


def test_api_get_not_found():
    response = requests.get(BASE_URL + "/job/999999", timeout=5)
    assert response.status_code == 404, (
        f"Expected HTTP 404 for missing job, got {response.status_code}. Response: {response.text}"
    )
    with sqlite3.connect(DB_PATH) as conn:
        maximum = conn.execute("SELECT COALESCE(MAX(id), 0) FROM jobs").fetchone()[0]
    missing = int(maximum) + secrets.randbelow(1000000) + 1000000
    response = requests.get(f"{BASE_URL}/job/{missing}", timeout=5)
    assert response.status_code == 404, f"Expected HTTP 404 for dynamic missing job {missing}"


def test_server_really_uses_wrapper_and_shared_library(tmp_path):
    # Replace the already-validated library with a verifier-generated implementation,
    # restart server.py, and require both the wrapper and API to observe its secret value.
    sentinel = float(secrets.randbelow(8000) + 10000) + 0.25
    source = tmp_path / "sentinel.c"
    replacement = tmp_path / "libaudiofeat.so"
    backup = tmp_path / "original_libaudiofeat.so"
    source.write_text(
        "float get_audio_feature(const char *filepath) { (void)filepath; return "
        + repr(sentinel) + "f; }\n",
        encoding="utf-8",
    )
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", str(replacement), str(source)],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    shutil.copy2(LIB_PATH, backup)
    restored = False
    try:
        stop_listener()
        os.replace(replacement, LIB_PATH)
        start_submitted_server()

        fixture = tmp_path / ("sentinel_" + uuid.uuid4().hex + ".wav")
        fixture.write_bytes(os.urandom(secrets.randbelow(2048) + 10))
        probe_wrapper_in_fresh_process(str(fixture), sentinel)
        process_and_check(str(fixture), sentinel)
    finally:
        stop_listener()
        if backup.exists():
            os.replace(backup, LIB_PATH)
            restored = True
        if restored:
            start_submitted_server()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
