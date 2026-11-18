#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import importlib
import importlib.machinery
import importlib.util
import json
import math
import os
import shutil
import sqlite3
import subprocess
import sys
import time
import uuid

import pytest

BASE = "/home/user/qa_env"
SRC = os.path.join(BASE, "src")
AUTH_SOURCE = os.path.join(SRC, "auth_hash.py")
SETUP_PY = os.path.join(SRC, "setup.py")
BENCH_PY = os.path.join(BASE, "bench.py")
METRICS = os.path.join(BASE, "results", "metrics.json")


def expected_hash(username, password):
    return hashlib.sha256(
        f"{username}{password}QA_SECURE_SALT_2024".encode("utf-8")
    ).hexdigest()


def test_db_v2_exists_and_schema():
    db_path = "/home/user/qa_env/db/users_v2.db"
    assert os.path.isfile(db_path), f"New database {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='secure_users';")
    table = cursor.fetchone()
    assert table is not None, "Table 'secure_users' does not exist in users_v2.db."

    cursor.execute("PRAGMA table_info(secure_users);")
    columns = {row[1]: row[2] for row in cursor.fetchall()}

    expected_columns = {
        "user_uuid": "TEXT",
        "username": "TEXT",
        "pass_hash": "TEXT",
    }

    for col_name, col_type in expected_columns.items():
        assert col_name in columns, f"Column '{col_name}' is missing in 'secure_users'."
        assert "TEXT" in columns[col_name].upper(), f"Column '{col_name}' should be of type TEXT."

    conn.close()


def test_db_v2_data():
    db_v1_path = "/home/user/qa_env/db/users_v1.db"
    db_v2_path = "/home/user/qa_env/db/users_v2.db"

    assert os.path.isfile(db_v1_path), f"Legacy database {db_v1_path} is missing."
    assert os.path.isfile(db_v2_path), f"New database {db_v2_path} is missing."

    conn_v1 = sqlite3.connect(db_v1_path)
    cursor_v1 = conn_v1.cursor()
    cursor_v1.execute("SELECT username, password FROM old_users;")
    old_users = cursor_v1.fetchall()
    conn_v1.close()

    conn_v2 = sqlite3.connect(db_v2_path)
    cursor_v2 = conn_v2.cursor()
    cursor_v2.execute("SELECT user_uuid, username, pass_hash FROM secure_users;")
    new_users = cursor_v2.fetchall()
    conn_v2.close()

    assert len(new_users) == len(old_users), f"Expected {len(old_users)} rows in secure_users, found {len(new_users)}."

    new_users_dict = {row[1]: {"uuid": row[0], "hash": row[2]} for row in new_users}

    for username, password in old_users:
        assert username in new_users_dict, f"User '{username}' was not migrated to users_v2.db."
        user_data = new_users_dict[username]

        try:
            uuid.UUID(user_data["uuid"], version=4)
        except ValueError:
            pytest.fail(f"user_uuid '{user_data['uuid']}' for user '{username}' is not a valid UUID4.")

        wanted = expected_hash(username, password)
        assert user_data["hash"] == wanted, (
            f"Hash for user '{username}' is incorrect. Expected {wanted}, got {user_data['hash']}."
        )


def test_python_module_and_generate_hash():
    assert os.path.isfile(AUTH_SOURCE), f"Python module {AUTH_SOURCE} is missing."

    spec = importlib.util.spec_from_file_location("auth_hash_source_under_test", AUTH_SOURCE)
    assert spec is not None and spec.loader is not None, "auth_hash.py cannot be loaded as a Python module."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    assert callable(getattr(module, "generate_hash", None)), "auth_hash.py must define callable generate_hash."
    cases = [
        ("testuser", "testpass"),
        ("audit_user_731", "P@ss-4821"),
        ("", "empty-user"),
        ("álîçé", "密碼-9"),
    ]
    for username, password in cases:
        result = module.generate_hash(username, password)
        assert result == expected_hash(username, password)
        assert isinstance(result, str) and len(result) == 64 and result == result.lower()


def test_cython_compiled_module():
    assert os.path.isfile(SETUP_PY), f"Cython build script {SETUP_PY} is missing."

    # A pre-positioned file is not sufficient: setup.py must actually recreate the extension.
    for path in glob.glob(os.path.join(SRC, "auth_hash*.so")) + glob.glob(os.path.join(SRC, "auth_hash*.pyd")):
        os.unlink(path)
    shutil.rmtree(os.path.join(SRC, "build"), ignore_errors=True)

    completed = subprocess.run(
        [sys.executable, SETUP_PY, "build_ext", "--inplace"],
        cwd=SRC,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert completed.returncode == 0, f"setup.py failed to build the extension:\n{completed.stdout}"

    so_files = glob.glob(os.path.join(SRC, "auth_hash.*.so"))
    assert len(so_files) > 0, "No compiled Cython module (auth_hash.*.so) found in /home/user/qa_env/src/."
    assert os.path.isfile(os.path.join(SRC, "auth_hash.c")), "The Cython-generated auth_hash.c file is missing."

    sys.modules.pop("auth_hash", None)
    sys.path.insert(0, SRC)
    try:
        importlib.invalidate_caches()
        module = importlib.import_module("auth_hash")
    finally:
        sys.path.pop(0)

    origin = os.path.realpath(module.__file__)
    assert any(origin == os.path.realpath(path) for path in so_files), (
        f"Imported auth_hash from {origin}, not from the compiled extension."
    )
    assert isinstance(module.__loader__, importlib.machinery.ExtensionFileLoader), (
        "auth_hash was not imported as a native extension module."
    )
    assert callable(getattr(module, "generate_hash", None))

    for username, password in [
        ("testuser", "testpass"),
        ("compiled_913", "secret!572"),
        ("用户", "pässword"),
    ]:
        assert module.generate_hash(username, password) == expected_hash(username, password)


def test_metrics_json():
    assert os.path.isfile(BENCH_PY), f"Benchmark script {BENCH_PY} is missing."

    profile_dir = "/tmp/bench_profile_counts"
    hook_dir = "/tmp/bench_profile_hook"
    shutil.rmtree(profile_dir, ignore_errors=True)
    shutil.rmtree(hook_dir, ignore_errors=True)
    os.makedirs(profile_dir)
    os.makedirs(hook_dir)

    # The hook observes generate_hash calls made by bench.py and any Python child
    # processes it starts. It also records the elapsed span containing those calls.
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
        f.write(r'''import atexit
import json
import os
import sys
import time

_counts = {"python": 0, "cython": 0}
_first = {"python": None, "cython": None}
_last = {"python": None, "cython": None}
_busy = False

def _record(kind):
    global _busy
    if _busy:
        return
    _busy = True
    try:
        now = time.perf_counter()
        _counts[kind] += 1
        if _first[kind] is None:
            _first[kind] = now
        _last[kind] = now
    finally:
        _busy = False

def _profile(frame, event, arg):
    try:
        if event == "call" and frame.f_code.co_name == "generate_hash":
            module_file = str(frame.f_globals.get("__file__", ""))
            _record("cython" if module_file.endswith((".so", ".pyd")) else "python")
        elif event == "c_call" and getattr(arg, "__name__", None) == "generate_hash":
            module = sys.modules.get(getattr(arg, "__module__", ""))
            module_file = str(getattr(module, "__file__", ""))
            _record("cython" if module_file.endswith((".so", ".pyd")) else "python")
    except Exception:
        pass
    return _profile

def _save():
    sys.setprofile(None)
    spans = {
        key: (0.0 if _first[key] is None else max(0.0, _last[key] - _first[key]))
        for key in _counts
    }
    try:
        with open(os.path.join("/tmp/bench_profile_counts", str(os.getpid()) + ".json"), "w") as out:
            json.dump({"counts": _counts, "spans": spans}, out)
    except Exception:
        pass

atexit.register(_save)
sys.setprofile(_profile)
''')

    env = os.environ.copy()
    env["PYTHONPATH"] = hook_dir + os.pathsep + env.get("PYTHONPATH", "")
    started_ns = time.time_ns()
    completed = subprocess.run(
        [sys.executable, BENCH_PY],
        cwd=BASE,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert completed.returncode == 0, f"bench.py failed:\n{completed.stdout}"

    assert os.path.isfile(METRICS), f"Metrics file {METRICS} is missing."
    assert os.stat(METRICS).st_mtime_ns >= started_ns - 1_000_000_000, (
        "metrics.json was not freshly generated by bench.py."
    )

    total_counts = {"python": 0, "cython": 0}
    total_spans = {"python": 0.0, "cython": 0.0}
    reports = glob.glob(os.path.join(profile_dir, "*.json"))
    assert reports, "No benchmark call profile was produced."
    for report in reports:
        with open(report) as f:
            observed = json.load(f)
        for kind in total_counts:
            total_counts[kind] += int(observed["counts"].get(kind, 0))
            total_spans[kind] += float(observed["spans"].get(kind, 0.0))

    assert total_counts["python"] >= 50_000, (
        f"bench.py made only {total_counts['python']} observed calls through the Python source; expected at least 50,000."
    )
    assert total_counts["cython"] >= 50_000, (
        f"bench.py made only {total_counts['cython']} observed calls through the compiled extension; expected at least 50,000."
    )

    with open(METRICS) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Metrics file {METRICS} is not valid JSON.")

    expected_keys = ["python_duration_seconds", "cython_duration_seconds", "cython_is_faster"]
    for key in expected_keys:
        assert key in data, f"Key '{key}' is missing from metrics.json."

    py_duration = data["python_duration_seconds"]
    cy_duration = data["cython_duration_seconds"]
    faster = data["cython_is_faster"]

    assert isinstance(py_duration, (int, float)) and not isinstance(py_duration, bool), (
        "python_duration_seconds must be a number."
    )
    assert isinstance(cy_duration, (int, float)) and not isinstance(cy_duration, bool), (
        "cython_duration_seconds must be a number."
    )
    assert isinstance(faster, bool), "cython_is_faster must be a boolean."
    assert math.isfinite(py_duration) and py_duration > 0
    assert math.isfinite(cy_duration) and cy_duration > 0
    assert faster == (cy_duration < py_duration), (
        "cython_is_faster must agree with the two measured durations."
    )

    # The reported intervals must plausibly contain the observed timed call spans.
    assert py_duration >= total_spans["python"] * 0.75
    assert cy_duration >= total_spans["cython"] * 0.75
    assert py_duration <= total_spans["python"] * 3.0 + 0.25
    assert cy_duration <= total_spans["cython"] * 3.0 + 0.25
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
