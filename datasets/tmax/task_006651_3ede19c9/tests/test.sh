#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import shutil
import sqlite3
import struct
import subprocess
import tempfile
import urllib.request

import pytest

WORKSPACE_DIR = "/home/user/workspace"
SO_PATH = os.path.join(WORKSPACE_DIR, "lib", "libauth.so")
DB_PATH = os.path.join(WORKSPACE_DIR, "auth.db")
LOG_PATH = os.path.join(WORKSPACE_DIR, "result.log")

EXPECTED_C = b'''#include <stdio.h>\n\nint generate_token(int seed) {\n    return (seed * 1337) ^ 0xDEAD;\n}\n'''
EXPECTED_MIGRATION = b'''import sqlite3\nimport os\n\ndef migrate():\n    db_path = '/home/user/workspace/auth.db'\n    conn = sqlite3.connect(db_path)\n    c = conn.cursor()\n    c.execute(\'\'\'CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT)\'\'\')\n    c.execute(\'\'\'INSERT INTO users (username) VALUES (\'admin\')\'\'\')\n    conn.commit()\n    conn.close()\n    print("Migration complete.")\n\nif __name__ == '__main__':\n    migrate()\n'''


def expected_token(seed):
    return (seed * 1337) ^ 0xDEAD


def fetch(seed):
    with urllib.request.urlopen(
        f"http://127.0.0.1:8000/token/{seed}", timeout=3
    ) as response:
        assert response.status == 200
        return response.read()


def test_provided_sources_were_not_modified():
    with open(os.path.join(WORKSPACE_DIR, "libauth.c"), "rb") as f:
        assert f.read() == EXPECTED_C, "libauth.c was modified"
    with open(os.path.join(WORKSPACE_DIR, "migrate.py"), "rb") as f:
        assert f.read() == EXPECTED_MIGRATION, "migrate.py was modified"


def test_libauth_so_exists_and_is_loadable():
    assert os.path.isfile(SO_PATH), (
        f"Shared library {SO_PATH} does not exist. Did you compile libauth.c correctly?"
    )
    with open(SO_PATH, "rb") as f:
        header = f.read(20)
    assert header[:4] == b"\x7fELF", "libauth.so is not an ELF binary"
    endian = "<" if header[5] == 1 else ">" if header[5] == 2 else None
    assert endian is not None
    assert struct.unpack(endian + "H", header[16:18])[0] == 3, (
        "libauth.so is not an ELF shared object"
    )

    lib = ctypes.CDLL(SO_PATH)
    generate_token = lib.generate_token
    generate_token.argtypes = [ctypes.c_int]
    generate_token.restype = ctypes.c_int
    for seed in (0, 1, 42, 317, 12345):
        assert generate_token(seed) == expected_token(seed)


def test_auth_db_exists_and_contains_migrated_schema():
    assert os.path.isfile(DB_PATH), (
        f"Database {DB_PATH} does not exist. Did you run migrate.py?"
    )
    with open(DB_PATH, "rb") as f:
        assert f.read(16) == b"SQLite format 3\x00", "auth.db is not a SQLite database"

    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    try:
        columns = conn.execute("PRAGMA table_info(users)").fetchall()
        assert [(row[1], row[2], row[5]) for row in columns] == [
            ("id", "INTEGER", 1),
            ("username", "TEXT", 0),
        ], "auth.db does not contain the migrated users schema"
        assert conn.execute(
            "SELECT COUNT(*) FROM users WHERE username = ?", ("admin",)
        ).fetchone()[0] >= 1, "auth.db does not contain the migrated admin user"
    finally:
        conn.close()


def test_flask_server_is_running_and_handles_derived_inputs():
    rng = random.SystemRandom()
    seeds = [rng.randrange(2, 30000) for _ in range(5)]
    for seed in seeds:
        body = fetch(seed)
        assert json.loads(body) == {"token": expected_token(seed)}


def test_result_log_contents_and_raw_response():
    assert os.path.isfile(LOG_PATH), (
        f"Result log {LOG_PATH} does not exist. Did you make the GET request and save the output?"
    )
    with open(LOG_PATH, "rb") as f:
        raw_content = f.read()
    content = raw_content.decode("utf-8").strip()
    assert content, f"File {LOG_PATH} is empty."

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"File {LOG_PATH} does not contain valid JSON. Content: {content}")

    assert "token" in data, (
        f"JSON in {LOG_PATH} is missing the 'token' key. Content: {data}"
    )
    expected = expected_token(42)
    assert data["token"] == expected, (
        f"Expected token {expected}, but got {data['token']}."
    )
    assert raw_content == fetch(42), (
        "result.log is not the exact raw response currently returned by the endpoint"
    )


def test_app_loads_and_calls_the_configured_ctypes_function():
    secret = random.SystemRandom().randrange(100000, 1000000)
    probe_source = f"int generate_token(int seed) {{ return seed ^ {secret}; }}\n"

    with tempfile.TemporaryDirectory(dir=os.path.dirname(SO_PATH)) as temp_dir:
        source = os.path.join(temp_dir, "probe.c")
        probe = os.path.join(temp_dir, "probe.so")
        backup = os.path.join(temp_dir, "original.so")
        with open(source, "w") as f:
            f.write(probe_source)
        subprocess.run(
            ["gcc", "-fPIC", "-shared", source, "-o", probe],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        os.replace(SO_PATH, backup)
        os.replace(probe, SO_PATH)
        try:
            check_script = r'''
import ctypes
import json
import os

real_cdll = ctypes.CDLL
loaded = []

def tracking_cdll(*args, **kwargs):
    obj = real_cdll(*args, **kwargs)
    loaded.append(obj)
    return obj

ctypes.CDLL = tracking_cdll
ctypes.cdll.LoadLibrary = tracking_cdll

import app

client = app.app.test_client()
secret = int(os.environ["PROBE_SECRET"])
for seed in (7, 42, 913, 22222):
    response = client.get(f"/token/{seed}")
    assert response.status_code == 200
    assert response.get_json() == {"token": seed ^ secret}

matching = []
for library in loaded:
    name = os.path.realpath(str(getattr(library, "_name", "")))
    if name.endswith(os.path.join("lib", "libauth.so")):
        matching.append(library)
assert matching, "app.py did not load lib/libauth.so through ctypes"

configured = False
for library in matching:
    function = library.generate_token
    if function.argtypes == [ctypes.c_int] and function.restype is ctypes.c_int:
        configured = True
assert configured, "generate_token argtypes/restype were not configured as c_int"
'''
            env = os.environ.copy()
            env["PROBE_SECRET"] = str(secret)
            env["PYTHONPATH"] = WORKSPACE_DIR
            completed = subprocess.run(
                ["python3", "-c", check_script],
                cwd=WORKSPACE_DIR,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            assert completed.returncode == 0, (
                "app.py did not use the configured C function:\n"
                + completed.stdout
                + completed.stderr
            )
        finally:
            if os.path.exists(SO_PATH):
                os.unlink(SO_PATH)
            os.replace(backup, SO_PATH)
TEST_EOF

status=0
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
