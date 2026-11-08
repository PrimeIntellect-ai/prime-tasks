#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import runpy
import secrets
import sqlite3
import urllib.request
from unittest import mock

import flask
import pytest

DB_PATH = "/home/user/metrics.db"
LIB_PATH = "/home/user/libmath.so"
SERVER_PATH = "/home/user/server.py"


def expected_nth_prime(n):
    assert n >= 1
    found = 0
    candidate = 1
    while found < n:
        candidate += 1
        prime = True
        divisor = 2
        while divisor * divisor <= candidate:
            if candidate % divisor == 0:
                prime = False
                break
            divisor += 1
        if prime:
            found += 1
    return candidate


def request_prime(n):
    url = f"http://localhost:8080/prime/{n}"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            return json.loads(response.read().decode())
    except Exception as e:
        pytest.fail(f"Failed to make request to {url}: {e}")


def matching_rows(n, result):
    with sqlite3.connect(DB_PATH) as conn:
        return conn.execute(
            "SELECT COUNT(*) FROM calculations WHERE n=? AND result=?",
            (n, result),
        ).fetchone()[0]


def test_libmath_so_exists_and_implements_nth_prime():
    assert os.path.isfile("/home/user/math_lib.cpp"), "The source file /home/user/math_lib.cpp does not exist."
    assert os.path.isfile(LIB_PATH), "The shared library /home/user/libmath.so does not exist."

    try:
        library = ctypes.CDLL(LIB_PATH)
    except OSError as e:
        pytest.fail(f"/home/user/libmath.so is not a loadable shared library: {e}")

    try:
        nth_prime = library.nth_prime
    except AttributeError:
        pytest.fail("/home/user/libmath.so does not export nth_prime.")

    nth_prime.argtypes = [ctypes.c_int]
    nth_prime.restype = ctypes.c_int

    choices = [n for n in range(1, 301) if n not in (5, 10)]
    for n in secrets.SystemRandom().sample(choices, 10):
        assert nth_prime(n) == expected_nth_prime(n), f"The C++ nth_prime function returned the wrong result for n={n}."


def test_server_pid_and_running():
    pid_file = "/home/user/server.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} does not exist."
    with open(pid_file, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), "PID file does not contain a valid integer."
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} is not running.")


def test_database_schema_migration():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(calculations);")
    columns = cursor.fetchall()

    timestamp_col = next((col for col in columns if col[1] == "timestamp"), None)
    assert timestamp_col is not None, "Column 'timestamp' was not added to 'calculations' table."
    assert timestamp_col[2].upper() == "DATETIME", "Column 'timestamp' is not of type DATETIME."
    assert timestamp_col[4] is not None and "CURRENT_TIMESTAMP" in timestamp_col[4].upper(), "Column 'timestamp' does not have DEFAULT CURRENT_TIMESTAMP."
    conn.close()


def test_server_uses_ctypes_library_for_route():
    assert os.path.isfile(SERVER_PATH), "The Flask server /home/user/server.py does not exist."

    loaded_paths = []
    calls = []

    class FakeFunction:
        def __init__(self):
            self.argtypes = None
            self.restype = None

        def __call__(self, n):
            value = n.value if isinstance(n, ctypes.c_int) else int(n)
            calls.append(value)
            return 1000003 + value

    fake_function = FakeFunction()

    class FakeLibrary:
        nth_prime = fake_function

    def fake_loader(path, *args, **kwargs):
        loaded_paths.append(os.fsdecode(path))
        return FakeLibrary()

    with mock.patch("ctypes.CDLL", side_effect=fake_loader), \
         mock.patch.object(ctypes.cdll, "LoadLibrary", side_effect=fake_loader), \
         mock.patch.object(flask.Flask, "run", lambda self, *args, **kwargs: None):
        namespace = runpy.run_path(SERVER_PATH)

    assert LIB_PATH in loaded_paths, "server.py did not load /home/user/libmath.so using ctypes."
    assert fake_function.argtypes is not None and list(fake_function.argtypes) == [ctypes.c_int], "server.py did not configure nth_prime argument types as c_int."
    assert fake_function.restype is ctypes.c_int, "server.py did not configure nth_prime return type as c_int."

    app = namespace.get("app")
    if not isinstance(app, flask.Flask):
        app = next((value for value in namespace.values() if isinstance(value, flask.Flask)), None)
    assert app is not None, "server.py did not create a Flask application."

    probe_n = secrets.SystemRandom().randint(301, 1000)
    response = app.test_client().get(f"/prime/{probe_n}")
    assert response.status_code == 200, "The Flask route failed when its ctypes function was exercised."
    assert response.get_json() == {"n": probe_n, "result": 1000003 + probe_n}, "The Flask route did not return the value produced by the ctypes nth_prime function."
    assert calls == [probe_n], "The /prime/<int:n> route did not invoke the configured ctypes nth_prime function exactly once."


def test_server_endpoint_and_db_logging():
    data = request_prime(5)
    assert data.get("n") == 5, f"Expected n=5 in response, got {data.get('n')}"
    assert data.get("result") == 11, f"Expected result=11 for 5th prime, got {data.get('result')}"

    data_10 = request_prime(10)
    assert data_10.get("n") == 10, f"Expected n=10 in response, got {data_10.get('n')}"
    assert data_10.get("result") == 29, f"Expected result=29 for 10th prime, got {data_10.get('result')}"

    assert matching_rows(5, 11) >= 1, "The request for n=5, result=11 was not logged in the database."
    assert matching_rows(10, 29) >= 1, "The request for n=10, result=29 was not logged in the database."

    choices = [n for n in range(11, 301) if n not in (5, 10)]
    for n in secrets.SystemRandom().sample(choices, 8):
        result = expected_nth_prime(n)
        before = matching_rows(n, result)
        dynamic_data = request_prime(n)
        assert dynamic_data == {"n": n, "result": result}, f"Incorrect JSON response for dynamically selected n={n}."
        after = matching_rows(n, result)
        assert after > before, f"The request for dynamically selected n={n} was not inserted into the database."


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
