#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import secrets
import signal
import sqlite3
import subprocess
import time
import urllib.error
import urllib.request

PROJECT = '/home/user/math_api'
DB_PATH = os.path.join(PROJECT, 'legacy.db')
APP_PATH = os.path.join(PROJECT, 'app.py')
TEST_PATH = os.path.join(PROJECT, 'test_app.py')


def test_schema_migration():
    """Verify the complete legacy dataset and schema were migrated."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."
    assert os.path.isfile(os.path.join(PROJECT, 'migrate.py')), "Migration script migrate.py does not exist."

    conn = sqlite3.connect(DB_PATH)
    try:
        c = conn.cursor()
        c.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = [row[0] for row in c.fetchall()]

        assert 'old_formulas' not in tables, "Table 'old_formulas' was not dropped."
        assert 'expressions' in tables, "Table 'expressions' was not created."

        c.execute("PRAGMA table_info(expressions)")
        info = c.fetchall()
        columns = {row[1] for row in info}
        expected_columns = {'id', 'name', 'expression', 'version'}
        assert expected_columns.issubset(columns), f"Table 'expressions' missing expected columns. Found: {columns}"

        version_info = next(row for row in info if row[1] == 'version')
        assert str(version_info[4]).strip("'\"") == '1', "version must default to 1."

        # Retain the original kinetic-energy assertion.
        c.execute("SELECT name, expression FROM expressions WHERE name='kinetic_energy'")
        row = c.fetchone()
        assert row is not None, "Migrated data for 'kinetic_energy' not found."
        assert row[1] == '0.5 * m * v**2', f"Migrated data is incorrect. Expected '0.5 * m * v**2', got {row[1]}"

        # Check every row that was present in old_formulas, not just one fixed row.
        c.execute("SELECT id, name, expression, version FROM expressions ORDER BY id")
        assert c.fetchall() == [
            (1, 'gravity', '9.81 * m', 1),
            (2, 'kinetic_energy', '0.5 * m * v**2', 1),
            (3, 'compound_interest', 'p * (1 + r/n)**(n*t)', 1),
        ], "The complete legacy dataset was not migrated faithfully."
    finally:
        conn.close()


def _post(payload):
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(
        'http://127.0.0.1:5000/evaluate',
        data=data,
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.status == 200, f"API returned status {response.status}"
        body = json.loads(response.read().decode('utf-8'))
        assert 'result' in body, "Response JSON missing 'result' key."
        assert isinstance(body['result'], (int, float)), "result must be numeric."
        return float(body['result'])


def test_api_evaluation():
    """Exercise database lookup and expression evaluation on varied inputs."""
    assert os.path.isfile(APP_PATH), f"API file {APP_PATH} does not exist."

    # A verifier-generated name and SymPy-style expression prevent an endpoint
    # hard-coded for the three shipped formulas from passing.
    nonce = 'verifier_' + secrets.token_hex(12)
    expression = 'sqrt(a**2 + b**2) + sin(theta) + log(z)'
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute(
            "INSERT INTO expressions (name, expression, version) VALUES (?, ?, 1)",
            (nonce, expression),
        )
        conn.commit()
    finally:
        conn.close()

    server = subprocess.Popen(
        ['python3', APP_PATH],
        cwd=PROJECT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    try:
        deadline = time.time() + 10
        while True:
            if server.poll() is not None:
                raise AssertionError(f"API server exited early with status {server.returncode}")
            try:
                # Any HTTP response proves the listener is ready.
                urllib.request.urlopen('http://127.0.0.1:5000/evaluate', timeout=0.5)
            except urllib.error.HTTPError:
                break
            except urllib.error.URLError:
                if time.time() >= deadline:
                    raise AssertionError("Failed to connect to API server on 127.0.0.1:5000")
                time.sleep(0.15)
            else:
                break

        cases = [
            ({'name': 'kinetic_energy', 'variables': {'m': 10.0, 'v': 5.0}}, 125.0),
            ({'name': 'kinetic_energy', 'variables': {'m': 3.25, 'v': 7.4}}, 0.5 * 3.25 * 7.4**2),
            ({'name': 'gravity', 'variables': {'m': 6.75}}, 9.81 * 6.75),
            (
                {'name': 'compound_interest', 'variables': {'p': 1200.0, 'r': 0.07, 'n': 12.0, 't': 3.0}},
                1200.0 * (1.0 + 0.07 / 12.0) ** (12.0 * 3.0),
            ),
        ]

        rng = secrets.SystemRandom()
        for _ in range(3):
            a = rng.uniform(1.0, 9.0)
            b = rng.uniform(1.0, 9.0)
            theta = rng.uniform(-1.0, 1.0)
            z = rng.uniform(1.1, 5.0)
            cases.append((
                {'name': nonce, 'variables': {'a': a, 'b': b, 'theta': theta, 'z': z}},
                math.sqrt(a**2 + b**2) + math.sin(theta) + math.log(z),
            ))

        for payload, expected in cases:
            actual = _post(payload)
            assert math.isclose(actual, expected, rel_tol=1e-8, abs_tol=1e-8), (
                f"Wrong result for {payload}: expected {expected}, got {actual}"
            )
    finally:
        if server.poll() is None:
            try:
                os.killpg(server.pid, signal.SIGTERM)
                server.wait(timeout=3)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(server.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute("DELETE FROM expressions WHERE name = ?", (nonce,))
            conn.commit()
        finally:
            conn.close()


def _run_student_tests():
    try:
        return subprocess.run(
            ['pytest', TEST_PATH],
            cwd=PROJECT,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f"Student pytest suite timed out: {exc}")


def test_pytest_suite_passes_and_detects_bad_api():
    """Require the submitted tests to pass and to reject an incorrect result."""
    assert os.path.isfile(TEST_PATH), f"Test file {TEST_PATH} does not exist."

    result = _run_student_tests()
    assert result.returncode == 0, f"Pytest suite failed to pass:\n{result.stdout}\n{result.stderr}"

    # Mutation check: empty, skipped, or assertion-free student suites also pass
    # against this deliberately broken API and must therefore be rejected.
    with open(APP_PATH, 'rb') as fh:
        original_app = fh.read()
    mutant = b'''from flask import Flask, jsonify\napp = Flask(__name__)\n@app.post("/evaluate")\ndef evaluate():\n    return jsonify(result=999.0)\nif __name__ == "__main__":\n    app.run(host="127.0.0.1", port=5000)\n'''
    try:
        with open(APP_PATH, 'wb') as fh:
            fh.write(mutant)
        for path in glob.glob(os.path.join(PROJECT, '__pycache__', 'app.*.pyc')):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        mutated_result = _run_student_tests()
        assert mutated_result.returncode != 0, (
            "The submitted pytest suite passes even when /evaluate always returns 999.0; "
            "it does not meaningfully test the required pythagoras evaluation."
        )
    finally:
        with open(APP_PATH, 'wb') as fh:
            fh.write(original_app)
        for path in glob.glob(os.path.join(PROJECT, '__pycache__', 'app.*.pyc')):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
